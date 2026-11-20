# frozen_string_literal: true

module TypstRails
  # Renders `.typ` views through a Rails controller, so app helpers, route
  # helpers, and partials work as in a request. Backs
  # {TypstRails.render_with_rails}.
  #
  # Nothing here loads Rails. ActionController is looked up when a render
  # happens, so typst-rails can be required before actionpack.
  #
  # @api private
  module RailsRendering
    # Raised as a {TypstRails::Error} message when ActionController is absent.
    MISSING_ACTION_CONTROLLER = "render_with_rails requires ActionController; use TypstRails.render"

    module_function

    # @param template [String, Symbol, Pathname] Rails template name
    # @param locals [Hash] view locals
    # @param assigns [Hash] view instance variables
    # @param controller [Class, nil] controller class to render with
    # @return [String] binary PDF data
    # @raise [TypstRails::Error] if ActionController is not loaded
    def render(template, locals: {}, assigns: {}, controller: nil)
      raise ArgumentError, "locals must be a Hash" unless locals.is_a?(Hash)
      raise ArgumentError, "assigns must be a Hash" unless assigns.is_a?(Hash)
      raise Error, MISSING_ACTION_CONTROLLER unless defined?(::ActionController::Base)

      controller ||= default_controller
      body = controller.render(template: template.to_s, formats: [:pdf], locals: locals, assigns: assigns)
      binary(body)
    end

    # ApplicationController when the app defines one that renders views,
    # otherwise ActionController::Base. An ApplicationController based on
    # ActionController::API cannot render templates, so it is skipped.
    #
    # @return [Class]
    def default_controller
      if Object.const_defined?(:ApplicationController)
        app_controller = ::ApplicationController
        return app_controller if app_controller.is_a?(Class) && app_controller <= ::ActionController::Base
      end

      ::ActionController::Base
    end

    # Returns the rendered body as a plain binary String. Rails may hand
    # back an ActionView::OutputBuffer or an ActiveSupport::SafeBuffer;
    # callers want bytes they can write to a file or attach.
    #
    # @param body [#to_s]
    # @return [String]
    def binary(body)
      String.new(body.to_s, encoding: Encoding::BINARY)
    end
  end
end
