# frozen_string_literal: true

require "test_helper"

module TypstRails
  # How the renderer applies DataSerializer: locals that cannot be serialized
  # raise, instance variables that cannot be serialized are left out with a
  # warning, and nothing is converted for templates that never read the data.
  class RendererDataPolicyTest < Minitest::Test
    DATA_SOURCE = '#let data = json("typst_data.json")'

    View = Struct.new(:assigns)

    # A value object with no JSON form, like a Money from a gem.
    class Money
      def initialize(cents)
        @cents = cents
      end
    end

    def setup
      force_cli_backend!
    end

    # Stubs the compiler, returning a proc that yields the parsed data file.
    def capture_data_file
      captured = nil
      Open3.stubs(:capture3).with do |*args|
        data_path = File.join(File.dirname(args.last), "typst_data.json")
        captured = File.exist?(data_path) ? JSON.parse(File.read(data_path)) : nil
        File.binwrite(args.last, "pdf")
        true
      end.returns(["", "", mock_status(true)])
      -> { captured }
    end

    # MARK: - Locals raise

    def test_an_unserializable_local_raises_with_its_key_path
      Open3.expects(:capture3).never
      locals = { line_items: [{ amount: 1 }, { amount: Money.new(2) }] }

      error = assert_raises(SerializationError) do
        Renderer.new(DATA_SOURCE).render(View.new({}), locals)
      end

      assert_equal "locals.line_items[1].amount", error.path
      assert_match(/\Alocals\.line_items\[1\]\.amount is a .*Money, which is not JSON-serializable\. /, error.message)
    end

    def test_an_unserializable_local_raises_without_a_view_context
      Open3.expects(:capture3).never

      error = assert_raises(SerializationError) do
        Renderer.new(DATA_SOURCE).render(nil, { total: Float::NAN })
      end

      assert_equal "locals.total", error.path
    end

    # Rails passes string keys in some paths; the path reads the same.
    def test_string_keyed_locals_are_named_the_same_way
      error = assert_raises(SerializationError) do
        Renderer.new(DATA_SOURCE).render(View.new({}), { "total" => Money.new(1) })
      end

      assert_equal "locals.total", error.path
    end

    def test_the_error_is_not_wrapped_by_collect_data
      error = assert_raises(SerializationError) do
        Renderer.new(DATA_SOURCE).send(:collect_data_for_typst, View.new({}), { bad: -> {} })
      end

      refute_includes error.message, "Failed to collect data"
    end

    # MARK: - Instance variables are left out

    def test_an_unserializable_instance_variable_is_left_out_with_a_warning
      data = capture_data_file
      view = View.new({ "title" => "Report", "exporter" => Money.new(1) })

      assert_output(nil, /TypstRails: Left 1 instance variable\(s\) out of typst_data.json/) do
        Renderer.new(DATA_SOURCE).render(view, {})
      end

      assert_equal({ "title" => "Report" }, data.call)
    end

    def test_one_warning_lists_every_omitted_instance_variable_and_its_path
      capture_data_file
      view = View.new({ "callback" => -> {}, "invoice" => { lines: [{ amount: Money.new(1) }] }, "ok" => 1 })

      _out, err = capture_io { Renderer.new(DATA_SOURCE).render(view, {}) }

      assert_equal 1, err.lines.size
      assert_includes err, "Left 2 instance variable(s) out of typst_data.json because they are not " \
                           "JSON-serializable: @callback (@callback is a Proc, which is not JSON-serializable); "
      assert_includes err, "@invoice (@invoice.lines[0].amount is a "
    end

    # Leaving out only the bad member would hand the template a half-built
    # value, so the whole variable goes.
    def test_the_whole_instance_variable_is_left_out_not_just_the_bad_member
      data = capture_data_file
      view = View.new({ "invoice" => { number: 7, total: Money.new(1) } })

      capture_io { Renderer.new(DATA_SOURCE).render(view, {}) }

      assert_nil data.call
    end

    def test_no_warning_when_every_instance_variable_serializes
      data = capture_data_file
      view = View.new({ "title" => "Report", "due" => Date.new(2024, 3, 9) })

      assert_output(nil, "") { Renderer.new(DATA_SOURCE).render(view, {}) }

      assert_equal({ "title" => "Report", "due" => "2024-03-09" }, data.call)
    end

    def test_a_local_shadowing_an_unserializable_instance_variable_suppresses_the_warning
      data = capture_data_file
      view = View.new({ "total" => Money.new(1) })

      assert_output(nil, "") { Renderer.new(DATA_SOURCE).render(view, { total: 100 }) }

      assert_equal({ "total" => 100 }, data.call)
    end

    # Rails keeps its own state in @_ variables and filters them from assigns;
    # gems add more (such as @_current_ability), which must not reach the
    # template or the warning.
    def test_underscore_prefixed_assigns_are_skipped_silently
      data = capture_data_file
      view = View.new({ "_current_ability" => Money.new(1), "_count" => 3, "title" => "x" })

      assert_output(nil, "") { Renderer.new(DATA_SOURCE).render(view, {}) }

      assert_equal({ "title" => "x" }, data.call)
    end

    def test_the_warning_goes_to_the_rails_logger_when_there_is_one
      capture_data_file
      logger = mock("logger")
      logger.expects(:warn).with(regexp_matches(/TypstRails: Left 1 instance variable\(s\).*@exporter/)).once
      rails = Module.new
      rails.define_singleton_method(:logger) { logger }

      with_defined_constant(:Rails, rails) do
        assert_output(nil, "") { Renderer.new(DATA_SOURCE).render(View.new({ "exporter" => Money.new(1) }), {}) }
      end
    end

    def test_a_failing_logger_falls_back_to_warn
      capture_data_file
      logger = Object.new
      def logger.warn(*)
        raise IOError, "log closed"
      end
      rails = Module.new
      rails.define_singleton_method(:logger) { logger }

      with_defined_constant(:Rails, rails) do
        assert_output(nil, /TypstRails: Left 1 instance variable/) do
          Renderer.new(DATA_SOURCE).render(View.new({ "exporter" => Money.new(1) }), {})
        end
      end
    end

    # MARK: - Templates that never read the data

    def test_nothing_is_converted_for_a_template_that_does_not_read_the_data
      mock_successful_typst_compilation
      DataSerializer.expects(:normalize).never

      assert_output(nil, "") do
        Renderer.new("= Plain").render(View.new({ "exporter" => Money.new(1) }), { bad: Money.new(2) })
      end
    end

    def test_nothing_is_converted_without_a_view_context_either
      mock_successful_typst_compilation
      DataSerializer.expects(:normalize).never

      Renderer.new("= Plain").render(nil, { bad: Money.new(2) })
    end

    def test_collect_data_returns_values_unconverted_for_such_templates
      date = Date.new(2024, 3, 9)

      data = Renderer.new("= Plain").send(:collect_data_for_typst, View.new({ "_internal" => 1, "due" => date }), {})

      assert_equal({ due: date }, data)
    end

    # MARK: - What reaches the file

    def test_the_data_file_holds_plain_json
      data = capture_data_file
      view = View.new({ "tags" => Set[:a, :b], "point" => Struct.new(:x, :y).new(1, 2) })

      Renderer.new(DATA_SOURCE).render(view, { status: :open, ratio: 0.5 })

      assert_equal({ "tags" => %w[a b], "point" => { "x" => 1, "y" => 2 }, "status" => "open", "ratio" => 0.5 },
                   data.call)
    end
  end
end
