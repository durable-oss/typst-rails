# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module TypstRails
  module Backends
    class CliTest < Minitest::Test
      def test_available_when_executable_on_path
        backend = Cli.new(executable_path: "typst")

        assert_predicate backend, :available?
      end

      def test_not_available_when_executable_missing
        backend = Cli.new(executable_path: "/no/such/typst-binary")

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
    end
  end
end
