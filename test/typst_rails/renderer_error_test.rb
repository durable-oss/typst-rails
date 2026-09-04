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

      force_cli_backend!
      Open3.stubs(:capture3).raises(Errno::ENOENT.new("typst"))

      error = assert_raises(Error) do
        renderer.render(nil, {})
      end

      assert_includes error.message, "Typst executable not found"
      assert_includes error.message, "Please ensure Typst is installed"
    end

    def test_compile_raises_error_when_execution_fails_unexpectedly
      renderer = Renderer.new("= Test")

      force_cli_backend!
      Open3.stubs(:capture3).raises(StandardError.new("boom"))

      error = assert_raises(Error) do
        renderer.render(nil, {})
      end

      assert_includes error.message, "Failed to execute Typst compiler"
      assert_includes error.message, "boom"
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
      force_cli_backend!
      Open3.stubs(:capture3).returns(["", "", mock_status(true)])

      error = assert_raises(Error) do
        renderer.render(nil, {})
      end

      assert_includes error.message, "output file was not created"
    end

    def test_compile_raises_error_when_pdf_is_empty
      renderer = Renderer.new("= Test")

      # Mock successful compilation but empty PDF
      force_cli_backend!
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

    # The data hash is serialized with #to_json before it is written. Raise from
    # there rather than stubbing File.write: whether the failure surfaces during
    # serialization or during the write depends on ActiveSupport being loaded,
    # and the gem does not depend on ActiveSupport.
    def test_compile_raises_error_on_json_serialization_failure
      renderer = Renderer.new("= Test")

      Hash.any_instance.stubs(:to_json).raises(JSON::GeneratorError.new("Cannot serialize"))

      error = assert_raises(Error) do
        renderer.render(nil, { data: "anything" })
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

    def test_collect_data_wraps_unexpected_errors
      renderer = Renderer.new("= Test")
      view_context = mock("view_context")
      view_context.stubs(:respond_to?).with(:assigns).returns(true)
      view_context.stubs(:assigns).raises(StandardError.new("assigns exploded"))

      error = assert_raises(Error) do
        renderer.send(:collect_data_for_typst, view_context, {})
      end

      assert_includes error.message, "Failed to collect data for Typst template"
      assert_includes error.message, "assigns exploded"
    end

    def test_cleanup_continues_despite_output_pdf_unlink_failure
      renderer = Renderer.new("= Test")

      mock_successful_typst_compilation

      original_unlink = File.method(:unlink)
      File.stubs(:unlink).with do |path|
        if path.end_with?("_output.pdf")
          true
        else
          original_unlink.call(path)
          false
        end
      end.raises(Errno::EACCES.new("Permission denied"))

      assert_output(nil, /Failed to clean up temp PDF file/) do
        renderer.render(nil, {})
      end
    end

    def test_cleanup_continues_despite_data_file_unlink_failure
      renderer = Renderer.new("= Test")

      mock_successful_typst_compilation

      original_unlink = File.method(:unlink)
      File.stubs(:unlink).with do |path|
        if path.end_with?("typst_data.json")
          true
        else
          original_unlink.call(path)
          false
        end
      end.raises(Errno::EACCES.new("Permission denied"))

      assert_output(nil, /Failed to clean up temp data file/) do
        renderer.render(nil, { title: "Test" })
      end
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
    # MARK: - Argument validation

    def test_render_rejects_a_nil_local_assigns
      renderer = Renderer.new("= Test")

      error = assert_raises(ArgumentError) { renderer.render(nil, nil) }

      assert_includes error.message, "local_assigns must be a Hash"
    end

    def test_render_rejects_an_array_local_assigns
      renderer = Renderer.new("= Test")

      assert_raises(ArgumentError) { renderer.render(nil, []) }
    end

    def test_initialize_error_message_mentions_nil_source
      error = assert_raises(ArgumentError) { Renderer.new(nil) }

      assert_includes error.message, "Source cannot be nil"
    end

    # MARK: - Error class contract

    # Callers rescue TypstRails::Error, so it must stay a StandardError
    # descendant; making it inherit from Exception would break every
    # `rescue => e` in user code.
    def test_error_is_a_standard_error
      assert_operator Error, :<, StandardError
    end

    def test_error_carries_its_message
      error = Error.new("boom")

      assert_equal "boom", error.message
    end

    # MARK: - Backend errors pass through unwrapped

    # A TypstRails::Error raised by a backend must reach the caller as-is, not
    # be re-wrapped into a second "Unexpected error" layer.
    def test_backend_errors_are_not_double_wrapped
      backend = stub("backend")
      backend.stubs(:compile).raises(Error, "original backend message")
      Backends::Registry.stubs(:resolve).returns(backend)

      renderer = Renderer.new("= Test")
      error = assert_raises(Error) { renderer.render(nil, {}) }

      assert_equal "original backend message", error.message
      refute_includes error.message, "Unexpected error"
    end

    # Anything that is not already a TypstRails::Error gets wrapped, with the
    # original class named so the cause is still diagnosable.
    def test_non_typst_errors_from_the_backend_are_wrapped_with_their_class
      backend = stub("backend")
      backend.stubs(:compile).raises(TypeError, "unexpected type")
      Backends::Registry.stubs(:resolve).returns(backend)

      renderer = Renderer.new("= Test")
      error = assert_raises(Error) { renderer.render(nil, {}) }

      assert_includes error.message, "Unexpected error during Typst compilation"
      assert_includes error.message, "TypeError"
    end

    # The original message is kept alongside the class so the cause survives
    # the wrapping.
    def test_wrapped_errors_retain_the_original_message
      backend = stub("backend")
      backend.stubs(:compile).raises(TypeError, "unexpected type")
      Backends::Registry.stubs(:resolve).returns(backend)

      error = assert_raises(Error) { Renderer.new("= Test").render(nil, {}) }

      assert_includes error.message, "unexpected type"
    end

    # A resolution failure (no backend available) must surface unchanged.
    def test_backend_resolution_failure_propagates
      Backends::Registry.stubs(:resolve).raises(Error, "No Typst backend is available.")

      renderer = Renderer.new("= Test")
      error = assert_raises(Error) { renderer.render(nil, {}) }

      assert_includes error.message, "No Typst backend is available"
    end

    # MARK: - Temp file cleanup on the error path

    # A failure must not leave the scratch .typ file behind.
    def test_temp_source_file_is_removed_when_the_backend_raises
      captured_path = nil
      backend = stub("backend")
      backend.stubs(:compile).with do |typ_path, _root|
        captured_path = typ_path
        true
      end.raises(Error, "compilation failed")
      Backends::Registry.stubs(:resolve).returns(backend)

      assert_raises(Error) { Renderer.new("= Test").render(nil, {}) }

      refute_nil captured_path
      refute_path_exists captured_path
    end

    def test_temp_data_file_is_removed_when_the_backend_raises
      captured_dir = nil
      backend = stub("backend")
      backend.stubs(:compile).with do |_typ_path, root|
        captured_dir = root
        true
      end.raises(Error, "compilation failed")
      Backends::Registry.stubs(:resolve).returns(backend)

      assert_raises(Error) { Renderer.new("= Test").render(nil, { title: "T" }) }

      refute_nil captured_dir
      refute_path_exists File.join(captured_dir, "typst_data.json")
    end

    # MARK: - JSON serialization failures

    # An object whose #to_json raises must produce a TypstRails::Error rather
    # than leaking the underlying serializer exception.
    def test_unserializable_value_produces_a_typst_rails_error
      force_cli_backend!
      unserializable = Object.new
      def unserializable.to_json(*)
        raise JSON::GeneratorError, "cannot serialize"
      end

      renderer = Renderer.new("= Test")
      error = assert_raises(Error) { renderer.render(nil, { bad: unserializable }) }

      assert_includes error.message, "Failed to serialize data to JSON"
    end

    # MARK: - collect_data_for_typst

    # A view context whose #assigns returns a non-Hash is ignored rather than
    # crashing the render.
    def test_non_hash_assigns_are_ignored
      renderer = Renderer.new("= Test")
      view = Struct.new(:assigns).new("not a hash")

      result = renderer.send(:collect_data_for_typst, view, { local: 1 })

      assert_equal({ local: 1 }, result)
    end

    def test_nil_assigns_are_ignored
      renderer = Renderer.new("= Test")
      view = Struct.new(:assigns).new(nil)

      result = renderer.send(:collect_data_for_typst, view, { local: 1 })

      assert_equal({ local: 1 }, result)
    end

    # An #assigns that raises is wrapped as a TypstRails::Error with context.
    def test_raising_assigns_is_wrapped_with_context
      renderer = Renderer.new("= Test")
      view_class = Class.new do
        def assigns
          raise "assigns exploded"
        end
      end
      view = view_class.new

      error = assert_raises(Error) { renderer.send(:collect_data_for_typst, view, {}) }

      assert_includes error.message, "Failed to collect data for Typst template"
      assert_includes error.message, "assigns exploded"
    end
  end
end
