# frozen_string_literal: true

require "test_helper"
require "typst_rails/handler"

module ActionView
  class OutputBuffer
    def initialize
      @buffer = +""
    end

    def <<(value)
      @buffer << value.to_s
      self
    end

    def to_s
      @buffer
    end
  end
end

module TypstRails
  class HandlerTest < Minitest::Test
    FakeTemplate = Struct.new(:source)

    class FakeView
      attr_reader :local_assigns

      def initialize(local_assigns = {})
        @local_assigns = local_assigns
        @output_buffer = nil
      end
    end

    def test_supports_streaming_is_false
      refute_predicate Handler, :supports_streaming?
    end

    def test_call_compiles_static_template_and_renders_via_renderer
      template = FakeTemplate.new("= Hello World")
      view = FakeView.new

      Renderer.expects(:new).with("= Hello World").returns(
        mock("renderer").tap { |r| r.expects(:render).with(view, {}).returns("static pdf") }
      )

      code = Handler.call(template, template.source)
      result = view.instance_eval(code)

      assert_equal "static pdf", result
    end

    def test_call_processes_erb_using_local_assigns_before_rendering
      template = FakeTemplate.new("= <%= local_assigns[:title] %>")
      view = FakeView.new(title: "Report")

      Renderer.expects(:new).with("= Report").returns(
        mock("renderer").tap { |r| r.expects(:render).with(view, { title: "Report" }).returns("erb pdf") }
      )

      code = Handler.call(template, template.source)
      result = view.instance_eval(code)

      assert_equal "erb pdf", result
    end

    def test_call_uses_template_source_when_source_argument_omitted
      template = FakeTemplate.new("= From Template Source")
      view = FakeView.new

      Renderer.expects(:new).with("= From Template Source").returns(
        mock("renderer").tap { |r| r.expects(:render).returns("pdf") }
      )

      code = Handler.call(template)
      view.instance_eval(code)
    end

    def test_call_restores_original_output_buffer_after_processing
      template = FakeTemplate.new("= Test")
      view = FakeView.new
      original_buffer = "original buffer content"
      view.instance_variable_set(:@output_buffer, original_buffer)

      Renderer.stubs(:new).returns(mock("renderer").tap { |r| r.stubs(:render).returns("pdf") })

      code = Handler.call(template, template.source)
      view.instance_eval(code)

      assert_equal original_buffer, view.instance_variable_get(:@output_buffer)
    end
    # MARK: - ERB semantics

    # Trim mode "-" is what Rails' own ERB handler uses; `<% ... -%>` must
    # swallow the trailing newline so generated Typst keeps its intended
    # line structure.
    def test_call_honours_erb_trim_mode
      template = FakeTemplate.new("<% if true -%>\n= Kept\n<% end -%>\n")
      view = FakeView.new
      captured = nil

      Renderer.expects(:new).with { |src| captured = src }.returns(
        mock("renderer").tap { |r| r.expects(:render).returns("pdf") }
      )

      view.instance_eval(Handler.call(template, template.source))

      assert_equal "= Kept\n", captured
    end

    def test_call_evaluates_erb_expression_tags
      template = FakeTemplate.new("= <%= 2 + 2 %>")
      view = FakeView.new
      captured = nil

      Renderer.expects(:new).with { |src| captured = src }.returns(
        mock("renderer").tap { |r| r.expects(:render).returns("pdf") }
      )

      view.instance_eval(Handler.call(template, template.source))

      assert_equal "= 4", captured
    end

    def test_call_evaluates_erb_loops
      template = FakeTemplate.new("<% 3.times do |i| %>#<%= i %> <% end %>")
      view = FakeView.new
      captured = nil

      Renderer.expects(:new).with { |src| captured = src }.returns(
        mock("renderer").tap { |r| r.expects(:render).returns("pdf") }
      )

      view.instance_eval(Handler.call(template, template.source))

      assert_equal "#0 #1 #2 ", captured
    end

    # ERB must not touch Typst's own "#" syntax, which is not an ERB tag.
    def test_call_leaves_typst_hash_syntax_untouched
      template = FakeTemplate.new('#let x = 1\n#link("https://ex.com")[text]')
      view = FakeView.new
      captured = nil

      Renderer.expects(:new).with { |src| captured = src }.returns(
        mock("renderer").tap { |r| r.expects(:render).returns("pdf") }
      )

      view.instance_eval(Handler.call(template, template.source))

      assert_equal '#let x = 1\n#link("https://ex.com")[text]', captured
    end

    def test_call_handles_an_empty_template
      template = FakeTemplate.new("")
      view = FakeView.new
      captured = nil

      Renderer.expects(:new).with { |src| captured = src }.returns(
        mock("renderer").tap { |r| r.expects(:render).returns("pdf") }
      )

      view.instance_eval(Handler.call(template, template.source))

      assert_equal "", captured
    end

    def test_call_preserves_utf8_content
      template = FakeTemplate.new("= 日本語 café")
      view = FakeView.new
      captured = nil

      Renderer.expects(:new).with { |src| captured = src }.returns(
        mock("renderer").tap { |r| r.expects(:render).returns("pdf") }
      )

      view.instance_eval(Handler.call(template, template.source))

      assert_equal "= 日本語 café", captured
    end

    # MARK: - Compiled output shape

    def test_call_returns_ruby_source_rather_than_rendering_eagerly
      template = FakeTemplate.new("= Hello")

      # No Renderer expectation: calling the handler must not render anything.
      code = Handler.call(template, template.source)

      assert_kind_of String, code
      assert_includes code, "TypstRails::Renderer"
    end

    def test_compiled_code_is_valid_ruby
      template = FakeTemplate.new("= <%= 1 %>")

      code = Handler.call(template, template.source)

      assert RubyVM::InstructionSequence.compile(code),
             "the handler must emit syntactically valid Ruby"
    end

    # MARK: - Output buffer handling

    # The handler swaps in a fresh buffer so a partial's in-progress buffer is
    # not corrupted, then restores it. When there was none, it must restore nil
    # rather than leaving the scratch buffer behind.
    def test_call_restores_a_nil_output_buffer
      template = FakeTemplate.new("= Test")
      view = FakeView.new

      Renderer.stubs(:new).returns(mock("renderer").tap { |r| r.stubs(:render).returns("pdf") })

      view.instance_eval(Handler.call(template, template.source))

      assert_nil view.instance_variable_get(:@output_buffer)
    end

    def test_call_restores_the_output_buffer_even_when_rendering_raises
      template = FakeTemplate.new("= Test")
      view = FakeView.new
      view.instance_variable_set(:@output_buffer, "original")

      Renderer.stubs(:new).returns(
        mock("renderer").tap { |r| r.stubs(:render).raises(Error, "compilation failed") }
      )

      assert_raises(Error) { view.instance_eval(Handler.call(template, template.source)) }

      # The buffer is restored before Renderer#render runs, so a render failure
      # must not leave the view holding the scratch buffer.
      assert_equal "original", view.instance_variable_get(:@output_buffer)
    end

    # MARK: - local_assigns plumbing

    def test_call_passes_empty_local_assigns_through
      template = FakeTemplate.new("= Static")
      view = FakeView.new

      Renderer.expects(:new).returns(
        mock("renderer").tap { |r| r.expects(:render).with(view, {}).returns("pdf") }
      )

      view.instance_eval(Handler.call(template, template.source))
    end

    def test_call_passes_the_view_itself_as_the_render_context
      template = FakeTemplate.new("= Static")
      view = FakeView.new(a: 1)

      Renderer.expects(:new).returns(
        mock("renderer").tap { |r| r.expects(:render).with(view, { a: 1 }).returns("pdf") }
      )

      view.instance_eval(Handler.call(template, template.source))
    end
  end
end
