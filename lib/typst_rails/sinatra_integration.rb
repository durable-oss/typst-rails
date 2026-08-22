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

      # Extend Sinatra with Typst rendering capabilities
      ::Sinatra::Base.class_eval do
        # Helper method to render Typst templates in Sinatra
        def typst(template, locals = {}, _options = {})
          typst_source = File.read(template)
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
