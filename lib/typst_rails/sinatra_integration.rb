# frozen_string_literal: true

require "typst_rails/template_rendering"

module TypstRails
  # Integration for Sinatra framework
  module SinatraIntegration
    # Simple view context wrapper providing the `assigns` reader that
    # Renderer expects, mirroring Rails' view context interface. Kept for
    # compatibility; the helper now goes through {TemplateRendering}.
    ViewContext = ::TypstRails::TemplateRendering::ViewContext

    def self.setup
      return unless defined?(::Sinatra)

      # Extend Sinatra with Typst rendering capabilities
      ::Sinatra::Base.class_eval do
        include ::TypstRails::Helpers

        # Renders a Typst template to PDF. The template runs through ERB
        # first, in the route's scope, with +locals+ as local variables;
        # +locals+ are also written to typst_data.json.
        def typst(template, locals = {}, _options = {})
          pdf_data = ::TypstRails::TemplateRendering.render_file(template, self, locals, locals)

          content_type "application/pdf"
          pdf_data
        end
      end
    end
  end
end
