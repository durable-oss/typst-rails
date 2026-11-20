# frozen_string_literal: true

require "test_helper"

module TypstRails
  # How the Renderer reports Typst's diagnostics: compile errors named after
  # the template, and warnings from successful compiles.
  class RendererDiagnosticsTest < Minitest::Test
    include TestHelpers

    TEMPLATE = "app/views/reports/show.pdf.typ"
    BROKEN_SOURCE = "= Title\n\nHello\n#let x = foo(1)\n#x\n"
    WARNING_SOURCE = "#set text(font: \"NoSuchFontXyz\")\nHello\n"

    def setup
      @original_configuration = TypstRails.configuration
      @warnings = []
      TypstRails.configure do |config|
        config.on_warning = ->(warnings, template) { @warnings << [warnings, template] }
      end
    end

    def teardown
      TypstRails.configuration = @original_configuration
    end

    # MARK: - Real CLI

    def test_cli_compile_error_names_the_template
      use_real_backend(:cli)

      error = assert_raises(CompileError) { Renderer.new(BROKEN_SOURCE, template: TEMPLATE).render(nil, {}) }

      assert_equal [TEMPLATE, 4, 9, "#let x = foo(1)"], [error.template, error.line, error.column, error.source_line]
      assert_match(/\A(?!.*typst_rails_).*#{Regexp.escape(TEMPLATE)}:4:9: unknown variable: foo/m, error.message)
    end

    def test_cli_compile_error_keeps_the_command_and_the_original_error
      use_real_backend(:cli)

      error = assert_raises(CompileError) { Renderer.new(BROKEN_SOURCE, template: TEMPLATE).render(nil, {}) }

      assert_equal "compile", error.command[1]
      assert_kind_of CompileError, error.cause
    end

    def test_cli_compile_error_without_a_template_names_inline_source
      use_real_backend(:cli)

      error = assert_raises(CompileError) { Renderer.new(BROKEN_SOURCE).render(nil, {}) }

      assert_nil error.template
      assert_includes error.message, "(inline source):4:9"
    end

    def test_cli_compile_error_in_an_imported_file_uses_a_root_relative_path
      use_real_backend(:cli)

      Dir.mktmpdir do |root|
        File.write(File.join(root, "lib.typ"), "#let f() = { panic(\"boom\") }\n")
        TypstRails.configuration.default_root_path = root

        error = assert_raises(CompileError) do
          Renderer.new("#import \"/lib.typ\": f\n#f()\n", template: TEMPLATE).render(nil, {})
        end

        assert_includes error.message, "Typst compilation failed in /lib.typ:1:13: panicked with: boom"
        assert_includes error.message, "while calling `f` at #{TEMPLATE}:2:1"
      end
    end

    def test_cli_warnings_reach_on_warning
      use_real_backend(:cli)

      pdf = Renderer.new(WARNING_SOURCE, template: TEMPLATE).render(nil, {})

      assert pdf.start_with?("%PDF-")
      assert_equal [TEMPLATE], @warnings.map(&:last)
      warning = @warnings.first.first.first

      assert_equal ["unknown font family: nosuchfontxyz", TEMPLATE, 1, 16],
                   [warning.message, warning.path, warning.line, warning.column]
    end

    def test_cli_clean_compile_does_not_call_on_warning
      use_real_backend(:cli)

      Renderer.new("= Fine").render(nil, {})

      assert_empty @warnings
    end

    # MARK: - Real gem

    def test_gem_compile_error_names_the_template
      use_real_backend(:gem)

      error = assert_raises(CompileError) { Renderer.new(BROKEN_SOURCE, template: TEMPLATE).render(nil, {}) }

      assert_equal [4, 9, nil], [error.line, error.column, error.command]
      assert_match(/\A(?!.*typst_rails_).*#{Regexp.escape(TEMPLATE)}:4:9: unknown variable: foo/m, error.message)
    end

    # The typst gem returns only the PDF on success, so there is nothing to
    # report. This documents the limitation; it is not a goal.
    def test_gem_warnings_are_not_reported
      use_real_backend(:gem)

      Renderer.new(WARNING_SOURCE, template: TEMPLATE).render(nil, {})

      assert_empty @warnings
    end

    # MARK: - on_warning handling (stubbed CLI)

    def test_on_warning_nil_ignores_warnings
      TypstRails.configuration.on_warning = nil
      mock_cli_success(stderr: "warning: careful\n")

      assert_equal "pdf", Renderer.new("= Test").render(nil, {})
    end

    def test_default_handler_is_used_without_configuration
      TypstRails.configuration = nil
      mock_cli_success(stderr: "warning: careful\n")
      Diagnostics.expects(:log_warnings).with { |warnings, template| warnings.map(&:message) == ["careful"] && template.nil? }

      Renderer.new("= Test").render(nil, {})
    end

    def test_an_on_warning_error_propagates_unchanged
      boom = Class.new(StandardError)
      TypstRails.configuration.on_warning = ->(*) { raise boom, "warnings are errors here" }
      mock_cli_success(stderr: "warning: careful\n")

      assert_raises(boom) { Renderer.new("= Test").render(nil, {}) }
    end

    def test_stderr_without_warnings_does_not_call_on_warning
      mock_cli_success(stderr: "some informational line\n")

      Renderer.new("= Test").render(nil, {})

      assert_empty @warnings
    end

    def test_compile_errors_are_logged_with_the_rewritten_message
      mock_failed_typst_compilation(stderr: "error: boom\n")
      Renderer.any_instance.expects(:log_error).with do |message|
        message.start_with?("Typst compilation failed: boom\n(while rendering #{TEMPLATE})")
      end

      assert_raises(CompileError) { Renderer.new("= Test", template: TEMPLATE).render(nil, {}) }
    end

    # MARK: - Renderer.new

    def test_template_is_optional_and_stringified
      assert_nil Renderer.new("= Test").template
      assert_equal "views/a.typ", Renderer.new("= Test", template: Pathname.new("views/a.typ")).template
    end

    private

    def use_real_backend(name)
      backend = Backends::Registry.backends[name]
      skip "the #{name} backend is not available" unless backend&.available?

      TypstRails.configuration.backend = name
    end

    def mock_cli_success(stderr:)
      force_cli_backend!
      Open3.stubs(:capture3).with do |*args|
        File.binwrite(args.last, "pdf") if args.last.end_with?(".pdf")
        true
      end.returns(["", stderr, mock_status(true)])
    end
  end
end
