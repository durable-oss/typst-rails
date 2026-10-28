# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "stringio"

module TypstRails
  module Backends
    class CliTest < Minitest::Test
      # MARK: - Availability
      #
      # These build a real directory of fake executables and point PATH at it,
      # so the result does not depend on whether Typst is installed here.

      def test_available_when_executable_on_path
        with_path_containing("typst") do
          assert_predicate Cli.new(executable_path: "typst"), :available?
        end
      end

      def test_not_available_when_executable_not_on_path
        with_path_containing("other") do
          refute_predicate Cli.new(executable_path: "typst"), :available?
        end
      end

      def test_available_when_executable_path_exists
        with_path_containing do |dir|
          path = make_executable(dir, "typst")

          assert_predicate Cli.new(executable_path: path), :available?
        end
      end

      def test_not_available_when_executable_missing
        refute_predicate Cli.new(executable_path: "/no/such/typst-binary"), :available?
      end

      def test_not_available_when_the_path_is_not_executable
        with_path_containing do |dir|
          path = File.join(dir, "typst")
          File.write(path, "")
          File.chmod(0o644, path)

          refute_predicate Cli.new(executable_path: path), :available?
        end
      end

      def test_not_available_when_the_path_is_a_directory
        Dir.mktmpdir do |dir|
          refute_predicate Cli.new(executable_path: dir), :available?
        end
      end

      def test_a_non_executable_file_on_path_is_skipped
        with_path_containing do |dir|
          File.write(File.join(dir, "typst"), "")

          refute_predicate Cli.new(executable_path: "typst"), :available?
        end
      end

      def test_available_searches_every_path_entry
        with_path_containing("typst") do |dir|
          with_env("PATH" => ["/no/such/dir", dir].join(File::PATH_SEPARATOR)) do
            assert_predicate Cli.new(executable_path: "typst"), :available?
          end
        end
      end

      def test_available_honours_pathext
        with_path_containing("typst.exe") do
          with_env("PATHEXT" => ".COM#{File::PATH_SEPARATOR}.exe") do
            assert_predicate Cli.new(executable_path: "typst"), :available?
          end
        end
      end

      def test_available_tolerates_an_unset_path
        with_env("PATH" => nil) do
          refute_predicate Cli.new(executable_path: "typst"), :available?
        end
      end

      # A bare name in the working directory is not what the compile command
      # would run, since process spawning searches PATH only.
      def test_a_bare_name_in_the_working_directory_is_not_enough
        with_path_containing do |dir|
          make_executable(dir, "typst")

          Dir.chdir(dir) do
            with_env("PATH" => "/no/such/dir") do
              refute_predicate Cli.new(executable_path: "typst"), :available?
            end
          end
        end
      end

      # The executable path is configuration, but it must still never reach
      # a shell.
      def test_available_does_not_run_a_shell
        backend = Cli.new(executable_path: "typst; touch pwned")
        backend.expects(:system).never
        backend.expects(:`).never

        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            refute_predicate backend, :available?
            refute_path_exists File.join(dir, "pwned")
          end
        end
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
        with_path_containing do |dir|
          explicit = make_executable(dir, "explicit-typst")
          TypstRails.configure { |c| c.typst_executable_path = "/no/such/config/typst" }

          assert_predicate Cli.new(executable_path: explicit), :available?
        end
      ensure
        reset_configuration!
      end

      def test_falls_back_to_configured_executable_path
        with_path_containing do |dir|
          configured = make_executable(dir, "configured-typst")
          TypstRails.configure { |c| c.typst_executable_path = configured }

          assert_predicate Cli.new, :available?
        end
      ensure
        reset_configuration!
      end

      def test_falls_back_to_bare_typst_when_configuration_is_absent
        TypstRails.configuration = nil

        with_path_containing("typst") do
          assert_predicate Cli.new, :available?
        end
        with_path_containing("not-typst") do
          refute_predicate Cli.new, :available?
        end
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

      # MARK: - Argument passing

      # The command is passed to Open3 as separate arguments, never as a shell
      # string, so paths containing spaces or shell metacharacters reach Typst
      # intact.
      def test_compile_passes_paths_with_spaces_as_single_arguments
        backend = Cli.new(executable_path: "typst")
        captured_cmd = nil

        Open3.stubs(:capture3).with do |*args|
          captured_cmd = args
          File.binwrite(args.last, "pdf bytes")
          true
        end.returns(["", "", mock_status(true)])

        Dir.mktmpdir("dir with spaces; $(x)") do |dir|
          typ_path = File.join(dir, "my doc.typ")
          File.write(typ_path, "= Test")
          backend.compile(typ_path, dir)

          assert_equal ["typst", "compile", "--root", dir, typ_path, File.join(dir, "my doc_output.pdf")],
                       captured_cmd
        end
      end

      def test_compile_returns_binary_pdf_bytes_unchanged
        backend = Cli.new
        bytes = "%PDF-1.7\n\x00\xFF\xFE binary".b

        Open3.stubs(:capture3).with do |*args|
          File.binwrite(args.last, bytes)
          true
        end.returns(["", "", mock_status(true)])

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Test")
          result = backend.compile(typ_path, dir)

          assert_equal bytes, result
          assert_equal Encoding::BINARY, result.encoding
        end
      end

      def test_compilation_failure_message_includes_stderr
        backend = Cli.new
        Open3.stubs(:capture3).returns(["", "error: unknown variable: foo", mock_status(false)])

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "#foo")

          error = assert_raises(Error) { backend.compile(typ_path, dir) }
          assert_includes error.message, "Stderr: error: unknown variable: foo"
        end
      end

      # A stale PDF left behind by an earlier run must not be mistaken for the
      # output of a compile that failed.
      def test_a_failed_compile_does_not_return_a_stale_output_file
        backend = Cli.new
        Open3.stubs(:capture3).returns(["", "boom", mock_status(false)])

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Test")
          File.binwrite(File.join(dir, "doc_output.pdf"), "stale")

          assert_raises(Error) { backend.compile(typ_path, dir) }
          refute_path_exists File.join(dir, "doc_output.pdf")
        end
      end

      def test_is_a_backend
        assert_kind_of Base, Cli.new
      end

      private

      def reset_configuration!
        TypstRails.configuration = nil
      end

      # Yields a temporary directory set as the only PATH entry, holding an
      # executable for each of +names+.
      def with_path_containing(*names)
        Dir.mktmpdir do |dir|
          names.each { |name| make_executable(dir, name) }
          with_env("PATH" => dir, "PATHEXT" => nil) { yield dir }
        end
      end

      def make_executable(dir, name)
        path = File.join(dir, name)
        File.write(path, "#!/bin/sh\n")
        File.chmod(0o755, path)
        path
      end

      def with_env(vars)
        original = vars.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
        vars.each { |key, value| ENV[key] = value }
        yield
      ensure
        original.each { |key, value| ENV[key] = value }
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
