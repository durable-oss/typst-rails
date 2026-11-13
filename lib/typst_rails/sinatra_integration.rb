# frozen_string_literal: true

module TypstRails
  # Integration for Sinatra framework
  module SinatraIntegration
    # Simple view context wrapper providing the `assigns` reader that
    # Renderer expects, mirroring Rails' view context interface.
    ViewContext = Struct.new(:assigns)

    def self.setup
      return unless defined?(::Sinatra)

      require "typst_rails/renderer"
      require "typst_rails/erb_source"

      # Extend Sinatra with Typst rendering capabilities
      ::Sinatra::Base.class_eval do
        include ::TypstRails::Helpers

        # Renders a Typst template to PDF. The template runs through ERB
        # first, in the route's scope, with +locals+ as local variables;
        # +locals+ are also written to typst_data.json.
        def typst(template, locals = {}, _options = {})
          typst_source = ::TypstRails::ErbSource.render(File.read(template), self, locals)
          renderer = ::TypstRails::Renderer.new(typst_source)

          # Sinatra doesn't have the same view context as Rails,
          # so we create a simple wrapper
          view_context = ::TypstRails::SinatraIntegration::ViewContext.new(locals)
          pdf_data = renderer.render(view_context, locals)

          content_type "application/pdf"
          pdf_data
        end
      end
    end
  end
end
