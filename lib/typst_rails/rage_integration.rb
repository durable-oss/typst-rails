# frozen_string_literal: true

require "typst_rails/renderer"
require "typst_rails/erb_source"

module TypstRails
  # Integration for the Rage framework.
  #
  # Rage controllers render JSON or plain text and have no template handlers,
  # so the integration adds a controller helper rather than a `.typ` handler.
  module RageIntegration
    # Mirrors the `assigns` reader Renderer expects from a view context, so
    # locals get the same JSON conversion (models, dates) as in Rails.
    ViewContext = Struct.new(:assigns)

    # Mixed into RageController::API by {RageIntegration.setup}. Include it
    # yourself if typst-rails loads before Rage's controllers are defined.
    #
    # @example
    #   class ReportsController < RageController::API
    #     def show
    #       @title = "Monthly Report"
    #       render_typst "app/views/reports/monthly.typ", { total: 42 }
    #     end
    #   end
    module ControllerHelpers
      include ::TypstRails::Helpers

      # Renders a Typst template and responds with the PDF.
      #
      # The template runs through ERB first, in the controller's scope, with
      # +locals+ as local variables; +locals+ are also written to
      # typst_data.json for templates that read it.
      #
      # @param template [String] path to the .typ file
      # @param locals [Hash] data for the template
      # @param status [Integer, Symbol, nil] response status
      # @return [void]
      # @raise [TypstRails::Error] if compilation fails
      def render_typst(template, locals = {}, status: nil)
        source = ::TypstRails::ErbSource.render(File.read(template), self, locals)
        pdf_data = ::TypstRails::Renderer.new(source).render(ViewContext.new(locals), locals)

        # Rage's render(plain:) sets text/plain, so override it afterwards.
        render plain: pdf_data, status: status
        headers["content-type"] = "application/pdf"
      end
    end

    # Adds {ControllerHelpers} to RageController::API, if it is loaded.
    #
    # @return [void]
    def self.setup
      return unless defined?(::Rage)
      return unless defined?(::RageController::API)
      return if ::RageController::API.include?(ControllerHelpers)

      ::RageController::API.include(ControllerHelpers)
      nil
    end
  end
end
