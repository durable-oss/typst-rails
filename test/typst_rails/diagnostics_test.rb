# frozen_string_literal: true

require "test_helper"

module TypstRails
  # The fixtures are real output captured from Typst 0.15: the CLI in both
  # diagnostic formats, and the message of the exception the `typst` gem
  # raises. They were produced with the working directory at "/", for a
  # template at /srv/app/typst/typst_rails_20261120-4242-abc123/template.typ
  # under the root /srv/app/typst, which also held lib.typ.
  class DiagnosticsTest < Minitest::Test
    FIXTURES = File.expand_path("../fixtures/diagnostics", __dir__)
    ROOT = "/srv/app/typst"
    RUN_DIR = "#{ROOT}/typst_rails_20261120-4242-abc123"
    TYP_PATH = "#{RUN_DIR}/template.typ"
    RAW_TEMPLATE_PATH = TYP_PATH.delete_prefix("/")

    def fixture(name)
      File.read(File.join(FIXTURES, "#{name}.txt"), encoding: "UTF-8")
    end

    def parse(name)
      Diagnostics.parse(fixture(name))
    end

    def rewriter(template: "app/views/reports/show.pdf.typ")
      Diagnostics::PathRewriter.new(
        typ_path: TYP_PATH, run_dir: RUN_DIR, root: ROOT, template: template, base_dir: "/"
      )
    end

    # MARK: - Parsing a single error

    %w[cli_human cli_short gem].each do |source|
      define_method("test_parses_an_unknown_variable_error_from_#{source}") do
        diagnostics = parse("#{source}_unknown_variable")

        assert_equal 1, diagnostics.size
        diagnostic = diagnostics.first

        assert_equal :error, diagnostic.severity
        assert_equal "unknown variable: foo", diagnostic.message
        assert_equal RAW_TEMPLATE_PATH, diagnostic.path
        assert_equal 4, diagnostic.line
        assert_equal 9, diagnostic.column
      end

      define_method("test_parses_every_error_from_#{source}") do
        diagnostics = parse("#{source}_multiple_errors")

        assert_equal([[1, 12], [2, 8], [2, 8]], diagnostics.map { |d| [d.line, d.column] })
        assert_equal ["expected expression", "expected expression", "expected semicolon or line break"],
                     diagnostics.map(&:message)
      end

      define_method("test_parses_errors_and_warnings_together_from_#{source}") do
        diagnostics = parse("#{source}_warning_and_error")

        assert_equal %i[error warning], diagnostics.map(&:severity).sort
        warning = diagnostics.find(&:warning?)

        assert_equal "unknown font family: nosuchfontxyz", warning.message
        assert_equal [1, 16], [warning.line, warning.column]
      end

      define_method("test_locates_an_error_in_an_imported_file_from_#{source}") do
        diagnostics = parse("#{source}_error_in_import")

        assert_equal 1, diagnostics.size
        assert_equal "panicked with: boom", diagnostics.first.message
        assert_equal "srv/app/typst/lib.typ", diagnostics.first.path
        assert_equal [1, 13], [diagnostics.first.line, diagnostics.first.column]
      end
    end

    # The gem lists warnings before errors; the CLI lists errors first.
    def test_keeps_the_order_typst_printed
      assert_equal %i[warning error], parse("gem_warning_and_error").map(&:severity)
      assert_equal %i[error warning], parse("cli_human_warning_and_error").map(&:severity)
    end

    def test_parses_a_warning_from_a_successful_cli_compile
      diagnostics = parse("cli_human_warning_only")

      assert_equal 1, diagnostics.size
      assert_predicate diagnostics.first, :warning?
      refute_predicate diagnostics.first, :error?
    end

    # MARK: - Hints

    def test_collects_hints_from_the_human_format
      %w[cli_human gem].each do |source|
        hints = parse("#{source}_hints").first.hints

        assert_equal 2, hints.size, source
        assert_match(/adding spaces between each letter/, hints.first)
        assert_match(/placing it in quotes/, hints.last)
      end
    end

    # The short format drops hints, which is why the CLI backend keeps the
    # default human format.
    def test_the_short_format_has_no_hints
      assert_empty parse("cli_short_hints").first.hints
    end

    # MARK: - Unrecognized output

    def test_unrecognized_output_yields_no_diagnostics
      assert_empty Diagnostics.parse("thread 'main' panicked at src/main.rs:1:1")
      assert_empty Diagnostics.parse("")
      assert_empty Diagnostics.parse(nil)
    end

    def test_a_header_without_a_location_still_parses
      diagnostic = Diagnostics.parse("error: failed to load file (access denied)\n").first

      assert_equal ["failed to load file (access denied)", nil, nil],
                   [diagnostic.message, diagnostic.path, diagnostic.location]
      assert_equal "error: failed to load file (access denied)", diagnostic.to_s
    end

    def test_source_excerpts_are_not_mistaken_for_short_diagnostics
      text = "error: boom\n  ┌─ a.typ:1:0\n  │\n1 │ x.typ:1:2: error: not real\n  │ ^\n"

      assert_equal ["boom"], Diagnostics.parse(text).map(&:message)
    end

    def test_strips_terminal_colors
      text = "\e[1;31merror\e[0m: \e[1mbad\e[0m\n  \e[34m┌─\e[0m a.typ:1:2\n"
      diagnostic = Diagnostics.parse(text).first

      assert_equal "bad", diagnostic.message
      assert_equal "a.typ:1:2", diagnostic.location
    end

    def test_tolerates_invalid_utf8
      text = (+"error: bad \xFF byte\n").force_encoding(Encoding::BINARY)

      assert_equal :error, Diagnostics.parse(text).first.severity
    end

    def test_parse_never_raises
      Diagnostics.stubs(:clean).raises(StandardError, "boom")

      assert_empty Diagnostics.parse("error: x")
    end

    def test_diagnostic_to_s
      diagnostic = parse("cli_short_unknown_variable").first

      assert_equal "#{RAW_TEMPLATE_PATH}:4:9: error: unknown variable: foo", diagnostic.to_s
    end

    # MARK: - Path rewriting

    %w[cli_human cli_short gem].each do |source|
      define_method("test_rewrites_the_template_path_in_#{source}_output") do
        text = rewriter.rewrite(fixture("#{source}_unknown_variable"))

        assert_includes text, "app/views/reports/show.pdf.typ:4:9"
        refute_includes text, "typst_rails_20261120"
      end

      define_method("test_rewrites_imported_files_to_root_relative_paths_in_#{source}_output") do
        text = rewriter.rewrite(fixture("#{source}_error_in_import"))

        assert_includes text, "/lib.typ:1:13"
        refute_includes text, "srv/app"
      end
    end

    def test_rewrites_call_traces
      cli = rewriter.rewrite(fixture("cli_human_error_in_import"))
      gem = rewriter.rewrite(fixture("gem_error_in_import"))

      assert_includes cli, "while calling `f` at app/views/reports/show.pdf.typ:4:1"
      assert_includes gem, "┌─ app/views/reports/show.pdf.typ:4:1"
    end

    def test_rewritten_output_parses_with_the_display_name
      diagnostic = Diagnostics.parse(rewriter.rewrite(fixture("cli_human_unknown_variable"))).first

      assert_equal "app/views/reports/show.pdf.typ", diagnostic.path
    end

    def test_names_inline_source_when_there_is_no_template
      text = rewriter(template: nil).rewrite(fixture("cli_short_unknown_variable"))

      assert_includes text, "(inline source):4:9: error"
    end

    def test_absolute_paths_in_messages_become_relative_to_the_template
      text = rewriter.rewrite("error: file not found (searched at #{RUN_DIR}/logo.png)\n" \
                              "error: bad file #{TYP_PATH}\n")

      assert_includes text, "(searched at logo.png)"
      assert_includes text, "bad file app/views/reports/show.pdf.typ"
    end

    def test_files_in_the_working_directory_become_relative_to_it
      assert_equal "typst_data.json", rewriter.display_path("#{RUN_DIR.delete_prefix("/")}/typst_data.json")
    end

    def test_files_outside_the_root_become_absolute
      assert_equal "/usr/share/x.typ", rewriter.display_path("usr/share/x.typ")
    end

    def test_relative_paths_resolve_against_the_base_directory
      rewriter = Diagnostics::PathRewriter.new(
        typ_path: TYP_PATH, run_dir: RUN_DIR, root: ROOT, base_dir: "/srv/app/current"
      )

      assert_equal Diagnostics::INLINE_SOURCE_NAME,
                   rewriter.display_path("../typst/typst_rails_20261120-4242-abc123/template.typ")
    end

    def test_rewriting_unrecognized_text_leaves_it_alone
      assert_equal "something odd happened", rewriter.rewrite("something odd happened")
    end

    def test_matches_symlinked_paths
      Dir.mktmpdir do |real|
        link = "#{real}-link"
        File.symlink(real, link)
        run_dir = File.join(link, "run")
        Dir.mkdir(run_dir)
        typ_path = File.join(run_dir, "template.typ")
        File.write(typ_path, "")
        rewriter = Diagnostics::PathRewriter.new(typ_path: typ_path, run_dir: run_dir, root: run_dir, template: "t.typ")

        assert_equal "t.typ", rewriter.display_path(File.join(File.realpath(real), "run", "template.typ"))
      ensure
        File.unlink(link) if link && File.symlink?(link)
      end
    end

    # MARK: - Default warning handler

    def test_log_warnings_uses_kernel_warn_without_rails
      warnings = parse("cli_human_warning_only")
      Kernel.expects(:warn).with do |message|
        message.include?("Typst reported 1 warning in app/views/a.typ") &&
          message.include?("warning: unknown font family: nosuchfontxyz")
      end

      Diagnostics.log_warnings(warnings, "app/views/a.typ")
    end

    def test_log_warnings_counts_several_warnings_and_omits_a_missing_template
      warnings = parse("cli_human_warning_only") * 2
      Kernel.expects(:warn).with { |message| message.start_with?("TypstRails: Typst reported 2 warnings:\n") }

      Diagnostics.log_warnings(warnings, nil)
    end

    def test_log_warnings_uses_the_rails_logger_when_present
      logger = mock("logger")
      logger.expects(:warn).with { |message| message.include?("unknown font family") }
      Kernel.expects(:warn).never

      with_rails_logger(logger) { Diagnostics.log_warnings(parse("cli_human_warning_only"), nil) }
    end

    def test_log_warnings_ignores_an_empty_list
      Kernel.expects(:warn).never

      Diagnostics.log_warnings([], nil)
      Diagnostics.log_warnings(nil, nil)
    end

    private

    def with_rails_logger(logger)
      had_rails = defined?(::Rails)
      unless had_rails
        Object.const_set(:Rails, Module.new do
          class << self
            attr_accessor :logger
          end
        end)
      end
      original = ::Rails.logger
      ::Rails.logger = logger
      yield
    ensure
      if had_rails
        ::Rails.logger = original
      else
        Object.send(:remove_const, :Rails)
      end
    end
  end
end
