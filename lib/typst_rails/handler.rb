# frozen_string_literal: true

require "erb"
require "typst_rails/renderer" # Loads the Renderer class

module TypstRails
  # Template handler for Typst (.typ) files.
  # This handler allows ERB preprocessing of Typst templates, enabling dynamic content
  # within Typst source files using standard Rails view instance variables and helpers.
  # The ERB-processed Typst source is then passed to the `TypstRails::Renderer`
  # for compilation into a PDF.
  class Handler
    # This method is called by ActionView to compile the template.
    # It returns a string of Ruby code that, when evaluated, will render the template.
    #
    # @param template [ActionView::Template] The template object, providing access to
    #   metadata like `source` (the raw template content) and `identifier`.
    # @param source [String, nil] The raw template source code. If nil, `template.source` is used.
    #   ActionView typically passes the source content as this second argument.
    # @return [String] A Ruby code string. This string will be evaluated by ActionView
    #   in the context of an `ActionView::Base` instance (the view context).
    def self.call(template, source = nil)
      actual_source = source || template.source

      # Configure ERB to behave like Rails' default ERB handler.
      # This involves setting the output buffer variable to '@output_buffer'
      # and enabling standard trim mode for ERB tags like '<%-' and '-%>'.
      erb_engine = ::ERB.new(
        actual_source,
        trim_mode: "-",           # Standard Rails trim mode (e.g., <% foo -%> removes trailing newline)
        eoutvar: "@output_buffer" # Specifies the output variable ERB should append to.
        # This makes it compatible with ActionView's rendering flow.
      )

      # `erb_engine.src` generates a string of Ruby code. This code, when executed,
      # evaluates the ERB template and appends results to the `eoutvar` (i.e., `@output_buffer`).
      erb_evaluation_code = erb_engine.src

      # The string returned by this `call` method is the final piece of Ruby code
      # that ActionView will `instance_eval`.
      # This code performs two main steps:
      # 1. Executes the `erb_evaluation_code` to process the Typst template through ERB,
      #    capturing the result. This allows dynamic Ruby evaluation within the .typ file.
      # 2. Passes the ERB-processed Typst source to our `TypstRails::Renderer`
      #    which then handles the actual Typst compilation.
      <<-RUBY_CODE
        # Preserve the current @output_buffer if one exists (e.g., if rendering a partial).
        # A new buffer is created for ERB processing of the Typst template to isolate its output.
        _original_typst_handler_output_buffer = @output_buffer
        @output_buffer = ActionView::OutputBuffer.new

        #{erb_evaluation_code}

        # After the above ERB code executes, @output_buffer contains the
        # ERB-processed Typst template source as a string.
        processed_typst_source = @output_buffer.to_s

        # Restore the original output buffer that was in place before this handler ran.
        @output_buffer = _original_typst_handler_output_buffer

        typst_renderer = ::TypstRails::Renderer.new(processed_typst_source)
        typst_renderer.render(self, local_assigns)
      RUBY_CODE
    end

    # Indicates whether this template handler supports streaming.
    # Typst compilation generates a complete PDF file; it's not inherently a streaming process
    # where chunks of output can be sent progressively. Therefore, streaming is not supported.
    #
    # @return [Boolean] false, as Typst rendering is not streamable.
    def self.supports_streaming?
      false
    end
  end
end
