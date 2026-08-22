# frozen_string_literal: true

require "test_helper"

module TypstRails
  class RendererTest < Minitest::Test
    def test_initialize_with_string_source
      source = "= Hello World"
      renderer = Renderer.new(source)

      assert_equal source, renderer.source
    end

    def test_initialize_with_non_string_source
      renderer = Renderer.new(123)

      assert_equal "123", renderer.source
    end

    def test_render_without_view_context
      source = "= Test Document"
      renderer = Renderer.new(source)

      mock_successful_typst_compilation(pdf_content: "test pdf")

      result = renderer.render(nil, { title: "Test" })

      assert_equal "test pdf", result
    end

    def test_render_with_view_context
      source = "= Test Document"
      renderer = Renderer.new(source)
      view_context = mock_view_context({ name: "Test" })

      mock_successful_typst_compilation

      result = renderer.render(view_context, { title: "Report" })

      refute_nil result
    end

    def test_render_with_empty_data
      source = "= Simple Document"
      renderer = Renderer.new(source)

      mock_successful_typst_compilation

      result = renderer.render(nil, {})

      refute_nil result
    end

    def test_render_creates_json_data_file_when_data_present
      source = "= Test"
      renderer = Renderer.new(source)
      data = { title: "My Title", count: 42 }

      # Track file operations
      json_written = nil
      File.expects(:write).with do |path, content|
        json_written = JSON.parse(content) if path.end_with?("typst_data.json")
        true
      end

      mock_successful_typst_compilation

      renderer.render(nil, data)

      assert_equal data.transform_keys(&:to_s), json_written
    end

    def test_render_does_not_create_json_file_when_data_empty
      source = "= Test"
      renderer = Renderer.new(source)

      File.expects(:write).with do |path, _|
        path.end_with?("typst_data.json")
      end.never

      mock_successful_typst_compilation

      renderer.render(nil, {})
    end

    def test_render_cleans_up_temp_files_on_success
      source = "= Test"
      renderer = Renderer.new(source)

      mock_successful_typst_compilation

      # Track created temp files
      temp_files_created = []
      original_tempfile_new = Tempfile.method(:new)
      Tempfile.define_singleton_method(:new) do |*args, **kwargs|
        file = original_tempfile_new.call(*args, **kwargs)
        temp_files_created << file.path
        file
      end

      renderer.render(nil, {})

      # Verify files are cleaned up
      temp_files_created.each do |path|
        refute_path_exists path, "Temp file #{path} should be cleaned up"
      end
    ensure
      # Restore Tempfile.new
      Tempfile.singleton_class.send(:remove_method, :new)
      Tempfile.define_singleton_method(:new, original_tempfile_new)
    end

    def test_render_cleans_up_temp_files_on_failure
      source = "= Test"
      renderer = Renderer.new(source)

      mock_failed_typst_compilation

      # Track created temp files
      temp_files = []

      Tempfile.stub :new, lambda { |*args|
        file = Tempfile.allocate
        file.send(:initialize, *args)
        temp_files << file.path
        file
      } do
        assert_raises(Error) { renderer.render(nil, {}) }
      end

      # Verify cleanup happened despite error
      temp_files.each do |path|
        refute_path_exists path, "Temp file should be cleaned up even on failure"
      end
    end

    def test_render_raises_error_on_compilation_failure
      source = "= Test"
      renderer = Renderer.new(source)

      mock_failed_typst_compilation(stderr: "syntax error on line 5")

      error = assert_raises(Error) do
        renderer.render(nil, {})
      end

      assert_includes error.message, "Typst compilation failed"
      assert_includes error.message, "syntax error on line 5"
    end

    def test_transform_value_for_json_serialization_with_date
      renderer = Renderer.new("test")
      date = Date.new(2025, 1, 15)
      result = renderer.send(:transform_value_for_json_serialization, date)

      assert_equal "2025-01-15", result
    end

    def test_transform_value_for_json_serialization_with_time
      renderer = Renderer.new("test")
      time = Time.new(2025, 1, 15, 10, 30, 45)
      result = renderer.send(:transform_value_for_json_serialization, time)

      assert_match(/2025-01-15T10:30:45/, result)
    end

    def test_transform_value_for_json_serialization_with_datetime
      renderer = Renderer.new("test")
      datetime = DateTime.new(2025, 1, 15, 10, 30, 45)
      result = renderer.send(:transform_value_for_json_serialization, datetime)

      assert_match(/2025-01-15T10:30:45/, result)
    end

    def test_transform_value_for_json_serialization_with_array
      renderer = Renderer.new("test")
      array = [1, "test", Date.new(2025, 1, 15)]
      result = renderer.send(:transform_value_for_json_serialization, array)

      assert_equal 1, result[0]
      assert_equal "test", result[1]
      assert_equal "2025-01-15", result[2]
    end

    def test_transform_value_for_json_serialization_with_hash
      renderer = Renderer.new("test")
      hash = { name: "Test", date: Date.new(2025, 1, 15) }
      result = renderer.send(:transform_value_for_json_serialization, hash)

      assert_equal "Test", result[:name]
      assert_equal "2025-01-15", result[:date]
    end

    def test_transform_value_for_json_serialization_with_nested_structures
      renderer = Renderer.new("test")
      data = {
        items: [
          { name: "Item 1", created_at: Date.new(2025, 1, 15) },
          { name: "Item 2", created_at: Date.new(2025, 1, 16) }
        ]
      }
      result = renderer.send(:transform_value_for_json_serialization, data)

      assert_equal "2025-01-15", result[:items][0][:created_at]
      assert_equal "2025-01-16", result[:items][1][:created_at]
    end

    def test_transform_value_for_json_serialization_with_active_record_object
      renderer = Renderer.new("test")

      active_record_module = Module.new
      base_class = Class.new do
        def as_json
          { "id" => 1, "name" => "Widget" }
        end
      end
      active_record_module.const_set(:Base, base_class)
      record = base_class.new

      with_defined_constant(:ActiveRecord, active_record_module) do
        result = renderer.send(:transform_value_for_json_serialization, record)

        assert_equal({ "id" => 1, "name" => "Widget" }, result)
      end
    end

    def test_collect_data_for_typst_with_view_context
      renderer = Renderer.new("test")
      view_context = mock_view_context({ user: "John" })
      locals = { title: "Report" }

      data = renderer.send(:collect_data_for_typst, view_context, locals)

      assert_equal "John", data[:user]
      assert_equal "Report", data[:title]
    end

    def test_collect_data_for_typst_locals_override_assigns
      renderer = Renderer.new("test")
      view_context = mock_view_context({ title: "Original" })
      locals = { title: "Override" }

      data = renderer.send(:collect_data_for_typst, view_context, locals)

      assert_equal "Override", data[:title]
    end

    def test_collect_data_for_typst_with_view_context_without_assigns
      renderer = Renderer.new("test")
      view_context = Object.new
      locals = { title: "Report" }

      data = renderer.send(:collect_data_for_typst, view_context, locals)

      assert_equal "Report", data[:title]
      refute data.key?(:user)
    end

    def test_method_missing_delegates_to_view_context
      renderer = Renderer.new("test")
      view_context = mock("view_context")
      view_context.expects(:some_helper).with("arg").returns("result")

      renderer.instance_variable_set(:@view_context, view_context)

      assert_equal "result", renderer.send(:some_helper, "arg")
    end

    def test_method_missing_raises_when_view_context_doesnt_respond
      renderer = Renderer.new("test")
      view_context = Object.new
      renderer.instance_variable_set(:@view_context, view_context)

      assert_raises(NoMethodError) do
        renderer.send(:nonexistent_method)
      end
    end

    def test_respond_to_missing_returns_true_for_view_context_methods
      renderer = Renderer.new("test")
      view_context = mock("view_context")
      view_context.stubs(:respond_to?).with(:some_helper, false).returns(true)

      renderer.instance_variable_set(:@view_context, view_context)

      assert_respond_to renderer, :some_helper
    end

    def test_respond_to_missing_returns_false_for_unknown_methods
      renderer = Renderer.new("test")
      view_context = Object.new
      renderer.instance_variable_set(:@view_context, view_context)

      refute_respond_to renderer, :nonexistent_method
    end

    def test_log_error_uses_rails_logger_when_available
      renderer = Renderer.new("test")
      rails_logger = mock("logger")
      rails_logger.expects(:error).with("TypstRails: Test error")

      rails_class = Class.new
      rails_class.define_singleton_method(:logger) { rails_logger }
      rails_class.define_singleton_method(:respond_to?) { |m| m == :logger }

      with_defined_constant(:Rails, rails_class) do
        renderer.send(:log_error, "Test error")
      end
    end

    def test_log_error_uses_warn_when_rails_not_available
      renderer = Renderer.new("test")

      with_undefined_constant(:Rails) do
        assert_output(nil, "TypstRails: Test error\n") do
          renderer.send(:log_error, "Test error")
        end
      end
    end

    private

    def mock_view_context(assigns_hash)
      context = mock("view_context")
      context.stubs(:assigns).returns(assigns_hash)
      context.stubs(:respond_to?).with(:assigns).returns(true)
      context
    end
  end
end
