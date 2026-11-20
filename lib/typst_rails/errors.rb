# frozen_string_literal: true

require "typst_rails/diagnostics"

module TypstRails
  # Error class for Typst-related errors.
  #
  # Raised when Typst compilation fails, when files cannot be created,
  # or when other Typst-specific errors occur during rendering. Compilation
  # failures raise the {CompileError} subclass, which carries Typst's
  # diagnostics.
  #
  # @example Handling Typst errors
  #   begin
  #     renderer.render(nil, data)
  #   rescue TypstRails::Error => e
  #     Rails.logger.error "Typst compilation failed: #{e.message}"
  #     render plain: "PDF generation failed", status: 500
  #   end
  class Error < StandardError; end

  # Raised when Typst rejects a template.
  #
  # The message names the template and the location of the first error,
  # followed by Typst's own output with the render's temporary paths
  # replaced by the template's name. The parsed diagnostics are available
  # as attributes.
  #
  # Line numbers count lines of the Typst source Typst compiled. For `.typ`
  # views and the Sinatra and Rage helpers, that is the template after ERB
  # evaluation, so a `<% %>` block that emits several lines (or none) can
  # shift them relative to the file on disk. {#source_line} shows the
  # compiled line.
  #
  # @example
  #   begin
  #     renderer.render(nil, data)
  #   rescue TypstRails::CompileError => e
  #     e.template     #=> "app/views/reports/show.pdf.typ"
  #     e.line         #=> 4
  #     e.column       #=> 9
  #     e.diagnostics.first.message #=> "unknown variable: foo"
  #   end
  class CompileError < Error
    # @return [Array<Diagnostics::Diagnostic>] every error and warning Typst
    #   reported, in the order it printed them. Empty when the output could
    #   not be parsed.
    attr_reader :diagnostics

    # @return [String, nil] display name of the template, such as
    #   "app/views/reports/show.pdf.typ", or nil if none was given
    attr_reader :template

    # @return [String] Typst's raw output, with temporary paths rewritten
    attr_reader :typst_message

    # @return [Array<String>, nil] the command line the CLI backend ran, for
    #   debugging; nil for other backends
    attr_reader :command

    # @return [String, nil] the compiled source line the first error points
    #   at, when that error is in the template itself
    attr_reader :source_line

    # @param typst_message [String, nil] Typst's diagnostic output
    # @param template [String, nil] display name of the template
    # @param command [Array<String>, nil] command line that was run
    # @param source [String, nil] the Typst source that was compiled, used
    #   to look up {#source_line}
    def initialize(typst_message = nil, template: nil, command: nil, source: nil)
      @typst_message = Diagnostics.clean(typst_message).strip
      @template = template
      @command = command
      @diagnostics = Diagnostics.parse(@typst_message)
      @source_line = find_source_line(source)
      super(build_message)
    end

    # @return [Array<Diagnostics::Diagnostic>] the errors among {#diagnostics}
    def errors
      diagnostics.select(&:error?)
    end

    # @return [Array<Diagnostics::Diagnostic>] the warnings among {#diagnostics}
    def warnings
      diagnostics.select(&:warning?)
    end

    # @return [Integer, nil] line of the first error, counted from 1
    def line
      first_error&.line
    end

    # @return [Integer, nil] column of the first error, counted from 0 as
    #   Typst reports it
    def column
      first_error&.column
    end

    private

    def first_error
      errors.first
    end

    def template_name
      template || Diagnostics::INLINE_SOURCE_NAME
    end

    def in_template?(diagnostic)
      diagnostic&.path == template_name
    end

    def find_source_line(source)
      return nil unless source && in_template?(first_error) && line&.positive?

      source.to_s.lines[line - 1]&.chomp
    end

    def build_message
      [summary, typst_message].reject(&:empty?).join("\n\n")
    end

    def summary
      error = first_error
      return template ? "Typst compilation failed for #{template}." : "Typst compilation failed." unless error

      text = "Typst compilation failed"
      text += " in #{error.location}" if error.location
      text += ": #{error.message}"
      if in_template?(error)
        text += "\n(Line numbers count lines of the compiled Typst source, after any ERB evaluation.)"
      elsif template
        text += "\n(while rendering #{template})"
      end
      text
    end
  end
end
