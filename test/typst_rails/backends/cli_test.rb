# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "stringio"

module TypstRails
  module Backends
    class CliTest < Minitest::Test
      # `available?` first checks for a literal path, then falls back to a
      # `which` lookup. Stub both so the result does not depend on whether the
      # machine running the tests happens to have Typst installed.
      def test_available_when_executable_on_path
        backend = Cli.new(executable_path: "typst")
        File.stubs(:exist?).with("typst").returns(false)
        backend.stubs(:system).with("which typst > /dev/null 2>&1").returns(true)

        assert_predicate backend, :available?
      end

      def test_available_when_executable_path_exists
        backend = Cli.new(executable_path: "/opt/typst/typst")
        File.stubs(:exist?).with("/opt/typst/typst").returns(true)

        assert_predicate backend, :available?
      end

      def test_not_available_when_executable_missing
        backend = Cli.new(executable_path: "/no/such/typst-binary")
        backend.stubs(:system).with("which /no/such/typst-binary > /dev/null 2>&1").returns(false)

        refute_predicate backend, :available?
      end

      def test_compile_returns_pdf_bytes_on_success
        backend = Cli.new

        Open3.stubs(:capture3).with do |*args|
          output_path = args.last
          File.binwrite(output_path, "pdf bytes") if output_path.end_with?(".pdf")
          true
        end.returns(["", "", mock_status(true)])

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Test")

          result = backend.compile(typ_path, dir)

          assert_equal "pdf bytes", result
        end
      end

      def test_compile_raises_when_executable_not_found
        backend = Cli.new

        Open3.stubs(:capture3).raises(Errno::ENOENT.new("typst"))

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Test")

          error = assert_raises(Error) { backend.compile(typ_path, dir) }
          assert_includes error.message, "Typst executable not found"
        end
      end

      def test_compile_raises_on_nonzero_exit
        backend = Cli.new

        Open3.stubs(:capture3).returns(["", "boom", mock_status(false)])

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Test")

          error = assert_raises(Error) { backend.compile(typ_path, dir) }
          assert_includes error.message, "Typst compilation failed"
          assert_includes error.message, "boom"
        end
      end

      def test_compile_raises_when_output_missing
        backend = Cli.new

        Open3.stubs(:capture3).returns(["", "", mock_status(true)])

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Test")

          error = assert_raises(Error) { backend.compile(typ_path, dir) }
          assert_includes error.message, "output file was not created"
        end
      end

      def test_compile_cleans_up_output_file
        backend = Cli.new
        output_path = nil

        Open3.stubs(:capture3).with do |*args|
          output_path = args.last
          File.binwrite(output_path, "pdf bytes") if output_path.end_with?(".pdf")
          true
        end.returns(["", "", mock_status(true)])

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Test")

          backend.compile(typ_path, dir)

          refute_path_exists output_path
        end
      end
      # MARK: - Executable path resolution

      # Precedence is: explicit constructor argument, then
      # TypstRails.configuration.typst_executable_path, then "typst".
      def test_explicit_executable_path_wins_over_configuration
        TypstRails.configure { |c| c.typst_executable_path = "/from/config/typst" }
        backend = Cli.new(executable_path: "/explicit/typst")
        File.stubs(:exist?).with("/explicit/typst").returns(true)

        assert_predicate backend, :available?
      ensure
        reset_configuration!
      end

      def test_falls_back_to_configured_executable_path
        TypstRails.configure { |c| c.typst_executable_path = "/from/config/typst" }
        backend = Cli.new
        File.stubs(:exist?).with("/from/config/typst").returns(true)

        assert_predicate backend, :available?
      ensure
        reset_configuration!
      end

      def test_falls_back_to_bare_typst_when_configuration_is_absent
        TypstRails.configuration = nil
        backend = Cli.new
        File.stubs(:exist?).with("typst").returns(true)

        assert_predicate backend, :available?
      ensure
        reset_configuration!
      end

      def test_configured_executable_path_is_used_in_the_compile_command
        TypstRails.configure { |c| c.typst_executable_path = "/custom/bin/typst" }
        backend = Cli.new
        captured_cmd = nil

        Open3.stubs(:capture3).with do |*args|
          captured_cmd = args
          output_path = args.last
          File.binwrite(output_path, "pdf bytes") if output_path.end_with?(".pdf")
          true
        end.returns(["", "", mock_status(true)])

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Test")
          backend.compile(typ_path, dir)
        end

        assert_equal "/custom/bin/typst", captured_cmd.first
      ensure
        reset_configuration!
      end

      # MARK: - Compile command construction

      def test_compile_passes_root_directory_to_typst
        backend = Cli.new
        captured_cmd = nil

        Open3.stubs(:capture3).with do |*args|
          captured_cmd = args
          output_path = args.last
          File.binwrite(output_path, "pdf bytes") if output_path.end_with?(".pdf")
          true
        end.returns(["", "", mock_status(true)])

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Test")
          backend.compile(typ_path, dir)

          assert_includes captured_cmd, "--root"
          assert_includes captured_cmd, dir
        end
      end

      def test_compile_passes_the_subcommand_and_source_path_to_typst
        backend = Cli.new
        captured_cmd = nil

        Open3.stubs(:capture3).with do |*args|
          captured_cmd = args
          output_path = args.last
          File.binwrite(output_path, "pdf bytes") if output_path.end_with?(".pdf")
          true
        end.returns(["", "", mock_status(true)])

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Test")
          backend.compile(typ_path, dir)

          assert_includes captured_cmd, "compile"
          assert_includes captured_cmd, typ_path
        end
      end

      # The output PDF is named after the source file so that concurrent
      # compilations in the same root directory do not clobber each other.
      def test_output_path_is_derived_from_the_source_basename
        backend = Cli.new
        output_path = nil

        Open3.stubs(:capture3).with do |*args|
          output_path = args.last
          File.binwrite(output_path, "pdf bytes") if output_path.end_with?(".pdf")
          true
        end.returns(["", "", mock_status(true)])

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "report.typ")
          File.write(typ_path, "= Test")
          backend.compile(typ_path, dir)
        end

        assert_equal "report_output.pdf", File.basename(output_path)
      end

      # MARK: - Failure modes

      def test_compile_raises_when_pdf_is_empty
        backend = Cli.new

        Open3.stubs(:capture3).with do |*args|
          output_path = args.last
          File.binwrite(output_path, "") if output_path.end_with?(".pdf")
          true
        end.returns(["", "", mock_status(true)])

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Test")

          error = assert_raises(Error) { backend.compile(typ_path, dir) }

          assert_includes error.message, "empty PDF"
        end
      end

      def test_compile_wraps_unexpected_execution_errors
        backend = Cli.new

        Open3.stubs(:capture3).raises(StandardError, "spawn blew up")

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Test")

          error = assert_raises(Error) { backend.compile(typ_path, dir) }

          assert_includes error.message, "Failed to execute Typst compiler"
          assert_includes error.message, "spawn blew up"
        end
      end

      def test_compilation_failure_message_includes_the_command
        backend = Cli.new

        Open3.stubs(:capture3).returns(["", "syntax error", mock_status(false)])

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Test")

          error = assert_raises(Error) { backend.compile(typ_path, dir) }

          assert_includes error.message, "Command:"
          assert_includes error.message, typ_path
        end
      end

      # An empty stderr should not produce a dangling "Stderr:" line.
      def test_compilation_failure_omits_stderr_section_when_stderr_is_empty
        backend = Cli.new

        Open3.stubs(:capture3).returns(["", "", mock_status(false)])

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Test")

          error = assert_raises(Error) { backend.compile(typ_path, dir) }

          assert_includes error.message, "Typst compilation failed"
          refute_includes error.message, "Stderr:"
        end
      end

      # MARK: - Cleanup

      def test_output_file_is_cleaned_up_even_when_compilation_fails
        backend = Cli.new
        output_path = nil

        # Typst wrote a partial file, then exited non-zero.
        Open3.stubs(:capture3).with do |*args|
          output_path = args.last
          File.binwrite(output_path, "partial") if output_path.end_with?(".pdf")
          true
        end.returns(["", "boom", mock_status(false)])

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Test")

          assert_raises(Error) { backend.compile(typ_path, dir) }
        end

        refute_path_exists output_path
      end

      # A failure to delete the scratch PDF must warn, not mask the real result.
      # The temp directory is managed manually here: stubbing File.unlink makes
      # Mocha treat Dir.mktmpdir's own teardown unlink as an unexpected call.
      def test_cleanup_failure_warns_and_does_not_raise
        backend = Cli.new
        dir = Dir.mktmpdir

        Open3.stubs(:capture3).with do |*args|
          output_path = args.last
          File.binwrite(output_path, "pdf bytes") if output_path.end_with?(".pdf")
          true
        end.returns(["", "", mock_status(true)])
        File.stubs(:unlink).raises(Errno::EACCES, "read-only filesystem")

        typ_path = File.join(dir, "doc.typ")
        File.write(typ_path, "= Test")

        result = nil
        stderr = capture_stderr { result = backend.compile(typ_path, dir) }

        assert_equal "pdf bytes", result, "a cleanup failure must not discard a good PDF"
        assert_includes stderr, "Failed to clean up temp PDF file"
      ensure
        File.unstub(:unlink)
        FileUtils.remove_entry(dir) if dir && File.directory?(dir)
      end

      private

      def reset_configuration!
        TypstRails.configuration = nil
      end

      def capture_stderr
        original = $stderr
        $stderr = StringIO.new
        yield
        $stderr.string
      ensure
        $stderr = original
      end
    end
  end
end
