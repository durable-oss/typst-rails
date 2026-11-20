# frozen_string_literal: true

module TypstRails
  # Parsing and path rewriting for the diagnostics Typst prints when it
  # compiles a document.
  #
  # Typst reports problems in one of two layouts. The default, "human", is
  # what both the `typst` CLI and the `typst` gem produce:
  #
  #   error: unknown variable: foo
  #     ┌─ template.typ:4:9
  #     │
  #   4 │ #let x = foo(1)
  #     │          ^^^
  #     │
  #     = hint: ...
  #
  # The CLI can also emit `--diagnostic-format short`, one line per
  # diagnostic, without hints or source excerpts:
  #
  #   template.typ:4:9: error: unknown variable: foo
  #
  # {.parse} understands both. Parsing is best-effort: text it does not
  # recognize is skipped, so callers always keep the raw output as well.
  module Diagnostics
    # One error or warning reported by Typst.
    #
    # @!attribute [r] severity
    #   @return [Symbol] `:error` or `:warning`
    # @!attribute [r] message
    #   @return [String] the diagnostic text, without the severity prefix
    # @!attribute [r] path
    #   @return [String, nil] the file the diagnostic points at, if any
    # @!attribute [r] line
    #   @return [Integer, nil] 1-based line number
    # @!attribute [r] column
    #   @return [Integer, nil] column number as Typst reports it, counted
    #   from 0 (Typst 0.15 prints the first column of a line as 0)
    # @!attribute [r] hints
    #   @return [Array<String>] hints Typst attached to the diagnostic
    Diagnostic = Struct.new(:severity, :message, :path, :line, :column, :hints, keyword_init: true) do
      # @return [Boolean] whether this is an error
      def error?
        severity == :error
      end

      # @return [Boolean] whether this is a warning
      def warning?
        severity == :warning
      end

      # @return [String, nil] "path:line:column", or as much of it as is known
      def location
        return nil unless path

        [path, line, column].compact.join(":")
      end

      # @return [String] a one-line summary, e.g.
      #   "app/views/reports/show.pdf.typ:4:9: error: unknown variable: foo"
      def to_s
        [location, "#{severity}: #{message}"].compact.join(": ")
      end
    end

    # Name used for the main template when no display name is known, for
    # example when a Renderer is built from a string.
    INLINE_SOURCE_NAME = "(inline source)"

    HEADER = /\A(error|warning): (.*)\z/.freeze
    LOCATION = /\A\s*┌─ (.+):(\d+):(\d+)\s*\z/.freeze
    HINT = /\A\s*= hint: (.*)\z/.freeze
    SHORT = /\A([^\s│][^│]*?):(\d+):(\d+): (error|warning): (.*)\z/.freeze
    # Headers for secondary notes, such as the call trace the `typst` gem
    # prints as "help: while calling `f`". Their locations belong to the
    # note, not to the preceding diagnostic.
    OTHER_HEADER = /\A[a-z]+(\[[^\]]*\])?: /.freeze
    ANSI_ESCAPE = /\e\[[0-9;]*[A-Za-z]/.freeze
    private_constant :HEADER, :LOCATION, :HINT, :SHORT, :OTHER_HEADER, :ANSI_ESCAPE

    class << self
      # Parses Typst diagnostic output.
      #
      # @param text [String, nil] stderr from the CLI, or the message of an
      #   exception raised by the `typst` gem
      # @return [Array<Diagnostic>] the diagnostics found, in the order Typst
      #   printed them; empty if none were recognized
      def parse(text)
        diagnostics = []
        current = nil

        clean(text).each_line do |raw_line|
          line = raw_line.chomp
          current = parse_line(line, current, diagnostics)
        end

        diagnostics
      rescue StandardError
        diagnostics || []
      end

      # Normalizes diagnostic text: valid UTF-8, no terminal color codes.
      #
      # @param text [String, nil]
      # @return [String]
      def clean(text)
        text = text.to_s.dup
        text.force_encoding(Encoding::UTF_8)
        text = text.scrub unless text.valid_encoding?
        text.gsub(ANSI_ESCAPE, "")
      end

      # The default {TypstRails::Configuration#on_warning} handler. Logs the
      # warnings through Rails.logger when it is available, and with
      # Kernel#warn otherwise.
      #
      # @param warnings [Array<Diagnostic>]
      # @param template [String, nil] display name of the template
      # @return [void]
      def log_warnings(warnings, template)
        return if warnings.nil? || warnings.empty?

        subject = template ? " in #{template}" : ""
        noun = warnings.size == 1 ? "warning" : "warnings"
        message = "TypstRails: Typst reported #{warnings.size} #{noun}#{subject}:\n" +
                  warnings.map { |w| "  #{w}" }.join("\n")

        if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
          ::Rails.logger.warn(message)
        else
          Kernel.warn(message)
        end
        nil
      end

      private

      # Returns the diagnostic that following location and hint lines
      # belong to, or nil when they belong to something else.
      def parse_line(line, current, diagnostics)
        if (match = HEADER.match(line))
          start_diagnostic(diagnostics, match[1], match[2])
        elsif (match = SHORT.match(line))
          start_diagnostic(diagnostics, match[4], match[5], match.captures[0, 3])
        elsif OTHER_HEADER.match?(line)
          nil
        else
          annotate(current, line)
          current
        end
      end

      # @param location [Array(String, String, String)] path, line and column
      def start_diagnostic(diagnostics, severity, message, location = [])
        path, line, column = location
        diagnostic = Diagnostic.new(
          severity: severity.to_sym, message: message, path: path,
          line: line&.to_i, column: column&.to_i, hints: []
        )
        diagnostics << diagnostic
        diagnostic
      end

      def annotate(diagnostic, line)
        return unless diagnostic

        if diagnostic.path.nil? && (match = LOCATION.match(line))
          diagnostic.path = match[1]
          diagnostic.line = match[2].to_i
          diagnostic.column = match[3].to_i
        elsif (match = HINT.match(line))
          diagnostic.hints << match[1]
        end
      end
    end

    # Replaces the paths of a render's temporary working directory in Typst
    # output with names that mean something to the developer.
    #
    # Each render compiles a copy of the template in a fresh directory, such
    # as /tmp/typst_rails_20261120-1234-abcd/template.typ, and Typst prints
    # paths relative to the process's working directory. This class maps
    # them back:
    #
    # - the template itself becomes its display name (for example
    #   "app/views/reports/show.pdf.typ"), or {INLINE_SOURCE_NAME};
    # - other files in the working directory become relative to it;
    # - files elsewhere under the Typst root become root-relative ("/lib.typ"),
    #   the form Typst source uses to refer to them;
    # - anything else becomes an absolute path.
    #
    # @api private
    class PathRewriter
      # "┌─ path:line:col" in the human format.
      LOCATION_LINE = /^(\s*┌─ )(.+):(\d+):(\d+)([ \t]*)$/.freeze
      # "while calling `f` at path:line:col" in the CLI's call traces.
      TRACE_LINE = /^(\s+[^\s│][^│\n]* at )(.+):(\d+):(\d+)([ \t]*)$/.freeze
      # "path:line:col: error: ..." in the short format.
      SHORT_LINE = /^([^\s│][^│\n]*?):(\d+):(\d+)(: (?:error|warning): )/.freeze
      private_constant :LOCATION_LINE, :TRACE_LINE, :SHORT_LINE

      # @param typ_path [String] the template file Typst compiled
      # @param run_dir [String] the render's working directory
      # @param root [String] the Typst root directory
      # @param template [String, nil] display name for the template
      # @param base_dir [String] directory Typst's relative paths are
      #   relative to (the process's working directory)
      def initialize(typ_path:, run_dir:, root:, template: nil, base_dir: Dir.pwd)
        @base_dir = base_dir
        @typ_paths = variants(typ_path)
        @run_dirs = variants(run_dir)
        @roots = variants(root)
        @template_name = template || INLINE_SOURCE_NAME
      end

      # @param text [String, nil] Typst diagnostic output
      # @return [String] the text with working-directory paths replaced
      def rewrite(text)
        text = Diagnostics.clean(text)
        text = text.gsub(LOCATION_LINE) { "#{Regexp.last_match(1)}#{location_suffix(Regexp.last_match)}" }
        text = text.gsub(TRACE_LINE) { "#{Regexp.last_match(1)}#{location_suffix(Regexp.last_match)}" }
        text = text.gsub(SHORT_LINE) do
          match = Regexp.last_match
          "#{display_path(match[1])}:#{match[2]}:#{match[3]}#{match[4]}"
        end
        strip_run_dir(text)
      end

      # @param path [String] a path as Typst printed it
      # @return [String] the path to show the developer
      def display_path(path)
        absolute = canonical(File.expand_path(path, @base_dir))
        return @template_name if @typ_paths.include?(absolute)

        relative_to(absolute, @run_dirs) ||
          root_relative(absolute) ||
          absolute
      end

      private

      def location_suffix(match)
        "#{display_path(match[2])}:#{match[3]}:#{match[4]}#{match[5]}"
      end

      # Absolute mentions, such as "file not found (searched at
      # /tmp/typst_rails_x/logo.png)", are shown relative to the template,
      # which is how the template refers to them.
      def strip_run_dir(text)
        @typ_paths.each { |path| text = text.gsub(path, @template_name) }
        @run_dirs.each { |dir| text = text.gsub("#{dir}#{File::SEPARATOR}", "") }
        text
      end

      def relative_to(path, dirs)
        dirs.each do |dir|
          prefix = "#{dir}#{File::SEPARATOR}"
          return path.delete_prefix(prefix) if path.start_with?(prefix)
        end
        nil
      end

      def root_relative(path)
        relative = relative_to(path, @roots)
        relative && "#{File::SEPARATOR}#{relative}"
      end

      # Typst may print the physical path of a directory reached through a
      # symlink (macOS's /var -> /private/var), so both spellings match.
      def variants(path)
        return [] if path.nil?

        expanded = File.expand_path(path.to_s)
        [expanded, canonical(expanded)].uniq
      end

      def canonical(path)
        File.realpath(path)
      rescue SystemCallError
        path
      end
    end
  end
end
