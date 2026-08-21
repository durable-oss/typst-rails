# frozen_string_literal: true

require "test_helper"

module TypstRails
  class RendererErrorTest < Minitest::Test
    def test_initialize_raises_error_with_nil_source
      error = assert_raises(ArgumentError) do
        Renderer.new(nil)
      end
      assert_equal "Source cannot be nil", error.message
    end

    def test_initialize_raises_error_with_too_large_source
      large_source = "a" * (Renderer::MAX_SOURCE_SIZE + 1)

      error = assert_raises(ArgumentError) do
        Renderer.new(large_source)
      end

      assert_includes error.message, "Source is too large"
      assert_includes error.message, "#{large_source.bytesize} bytes"
    end

    def test_render_raises_error_with_non_hash_local_assigns
      renderer = Renderer.new("= Test")

      error = assert_raises(ArgumentError) do
        renderer.render(nil, "not a hash")
      end

      assert_equal "local_assigns must be a Hash", error.message
    end

    def test_render_raises_error_with_empty_source
      renderer = Renderer.new("")

      error = assert_raises(ArgumentError) do
        renderer.render(nil, {})
      end

      assert_equal "Source is empty", error.message
    end

    def test_compile_raises_error_when_typst_not_found
      renderer = Renderer.new("= Test")

      Open3.stubs(:capture3).raises(Errno::ENOENT.new("typst"))

      error = assert_raises(Error) do
        renderer.render(nil, {})
      end

      assert_includes error.message, "Typst executable not found"
      assert_includes error.message, "Please ensure Typst is installed"
    end

    def test_compile_raises_error_on_compilation_failure
      renderer = Renderer.new("= Test")

      mock_failed_typst_compilation(stderr: "error: unexpected token")

      error = assert_raises(Error) do
        renderer.render(nil, {})
      end

      assert_includes error.message, "Typst compilation failed"
      assert_includes error.message, "unexpected token"
    end

    def test_compile_raises_error_when_output_file_not_created
      renderer = Renderer.new("= Test")

      # Mock successful status but don't create the output file
      Open3.stubs(:capture3).returns(["", "", mock_status(true)])

      error = assert_raises(Error) do
        renderer.render(nil, {})
      end

      assert_includes error.message, "output file was not created"
    end

    def test_compile_raises_error_when_pdf_is_empty
      renderer = Renderer.new("= Test")

      # Mock successful compilation but empty PDF
      Open3.stubs(:capture3).with do |*args|
        output_path = args.last
        File.binwrite(output_path, "") if output_path.end_with?(".pdf")
        true
      end.returns(["", "", mock_status(true)])

      error = assert_raises(Error) do
        renderer.render(nil, {})
      end

      assert_includes error.message, "produced an empty PDF"
    end

    def test_compile_raises_error_on_json_serialization_failure
      renderer = Renderer.new("= Test")

      # Create an object that cannot be serialized to JSON
      unserializable_object = Object.new
      def unserializable_object.to_json(*_args)
        raise JSON::GeneratorError, "Cannot serialize"
      end

      File.expects(:write).with do |path, _content|
        path.end_with?("typst_data.json")
      end.raises(JSON::GeneratorError.new("Cannot serialize"))

      error = assert_raises(Error) do
        renderer.render(nil, { data: unserializable_object })
      end

      assert_includes error.message, "Failed to serialize data to JSON"
    end

    def test_compile_raises_error_on_file_write_failure
      renderer = Renderer.new("= Test")

      File.stubs(:write).with do |path, _content|
        path.end_with?("typst_data.json")
      end.raises(Errno::EACCES.new("Permission denied"))

      error = assert_raises(Error) do
        renderer.render(nil, { data: "test" })
      end

      assert_includes error.message, "Failed to write data file"
    end

    def test_compile_wraps_unexpected_errors
      renderer = Renderer.new("= Test")

      Tempfile.stubs(:new).raises(StandardError.new("Unexpected error"))

      error = assert_raises(Error) do
        renderer.render(nil, {})
      end

      assert_includes error.message, "Unexpected error during Typst compilation"
      assert_includes error.message, "StandardError"
    end

    def test_collect_data_raises_error_with_non_hash_local_assigns
      renderer = Renderer.new("= Test")
      view_context = mock("view_context")

      error = assert_raises(ArgumentError) do
        renderer.send(:collect_data_for_typst, view_context, "not a hash")
      end

      assert_equal "local_assigns must be a Hash", error.message
    end

    def test_cleanup_continues_despite_errors
      renderer = Renderer.new("= Test")

      mock_failed_typst_compilation

      # Stub unlink to raise errors
      files_unlinked = []
      Tempfile.any_instance.stubs(:unlink).with do
        files_unlinked << true
        raise Errno::EACCES, "Permission denied"
      end

      assert_output(nil, /Failed to clean up/) do
        assert_raises(Error) do
          renderer.render(nil, {})
        end
      end
    end

    def test_log_error_handles_nil_message
      renderer = Renderer.new("= Test")

      # Should not raise error
      assert_silent do
        renderer.send(:log_error, nil)
      end
    end

    def test_log_error_handles_empty_message
      renderer = Renderer.new("= Test")

      # Should not raise error
      assert_silent do
        renderer.send(:log_error, "")
      end
    end

    def test_log_error_falls_back_to_warn_when_rails_logger_fails
      renderer = Renderer.new("= Test")

      rails_logger = mock("logger")
      rails_logger.stubs(:error).raises(StandardError.new("Logger failed"))

      rails_class = Class.new
      rails_class.define_singleton_method(:logger) { rails_logger }
      rails_class.define_singleton_method(:respond_to?) { |m| m == :logger }

      with_defined_constant(:Rails, rails_class) do
        assert_output(nil, /TypstRails: Test error/) do
          renderer.send(:log_error, "Test error")
        end
      end
    end
  end
end
