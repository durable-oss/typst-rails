# frozen_string_literal: true

require "test_helper"

module TypstRails
  class CompileErrorTest < Minitest::Test
    TEMPLATE = "app/views/reports/show.pdf.typ"

    HUMAN_OUTPUT = <<~TEXT
      error: unknown variable: foo
        ┌─ #{TEMPLATE}:4:9
        │
      4 │ #let x = foo(1)
        │          ^^^

      warning: unknown font family: nosuchfontxyz
        ┌─ #{TEMPLATE}:1:16
        │
      1 │ #set text(font: "NoSuchFontXyz")
        │                 ^^^^^^^^^^^^^^^
    TEXT

    SOURCE = "#set text(font: \"NoSuchFontXyz\")\n\nHello\n#let x = foo(1)\n#x\n"

    def build(message = HUMAN_OUTPUT, **options)
      CompileError.new(message, template: TEMPLATE, source: SOURCE, **options)
    end

    def test_is_a_typst_rails_error
      assert_operator CompileError, :<, Error
      assert_raises(Error) { raise build }
    end

    def test_exposes_the_first_error_location
      error = build

      assert_equal 4, error.line
      assert_equal 9, error.column
      assert_equal TEMPLATE, error.template
    end

    def test_separates_errors_from_warnings
      error = build

      assert_equal ["unknown variable: foo"], error.errors.map(&:message)
      assert_equal ["unknown font family: nosuchfontxyz"], error.warnings.map(&:message)
      assert_equal 2, error.diagnostics.size
    end

    def test_message_names_the_template_and_location
      message = build.message

      assert message.start_with?("Typst compilation failed in #{TEMPLATE}:4:9: unknown variable: foo\n")
      assert_includes message, "after any ERB evaluation"
      assert_includes message, "4 │ #let x = foo(1)"
    end

    def test_typst_message_is_kept_verbatim_without_trailing_whitespace
      assert_equal HUMAN_OUTPUT.strip, build.typst_message
    end

    def test_source_line_is_the_compiled_line_the_error_points_at
      assert_equal "#let x = foo(1)", build.source_line
    end

    def test_no_source_line_without_source
      assert_nil CompileError.new(HUMAN_OUTPUT, template: TEMPLATE).source_line
    end

    def test_no_source_line_when_the_error_is_in_another_file
      error = CompileError.new("error: boom\n  ┌─ /lib.typ:1:13\n", template: TEMPLATE, source: SOURCE)

      assert_nil error.source_line
      assert error.message.start_with?("Typst compilation failed in /lib.typ:1:13: boom\n(while rendering #{TEMPLATE})\n")
      refute_includes error.message, "ERB"
    end

    def test_no_source_line_when_the_line_is_out_of_range
      error = CompileError.new("error: boom\n  ┌─ #{TEMPLATE}:99:0\n", template: TEMPLATE, source: SOURCE)

      assert_nil error.source_line
    end

    def test_inline_source_is_matched_without_a_template
      error = CompileError.new("error: boom\n  ┌─ (inline source):3:0\n", source: SOURCE)

      assert_equal "Hello", error.source_line
      assert_nil error.template
    end

    def test_unrecognized_output_keeps_the_raw_message
      error = build("thread 'main' panicked")

      assert_empty error.diagnostics
      assert_equal [nil, nil], [error.line, error.column]
      assert_equal "Typst compilation failed for #{TEMPLATE}.\n\nthread 'main' panicked", error.message
    end

    def test_empty_output_without_a_template
      error = CompileError.new("")

      assert_equal "Typst compilation failed.", error.message
      assert_equal "", error.typst_message
    end

    def test_command_is_available_but_not_in_the_message
      command = ["typst", "compile", "--root", "/tmp/x", "/tmp/x/template.typ", "/tmp/x/out.pdf"]
      error = build(command: command)

      assert_equal command, error.command
      refute_includes error.message, "/tmp/x"
    end

    def test_raise_with_a_message_string
      error = assert_raises(CompileError) { raise CompileError, "error: boom" }

      assert_equal "boom", error.errors.first.message
    end
  end
end
