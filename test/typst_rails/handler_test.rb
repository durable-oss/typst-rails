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
  end
end
