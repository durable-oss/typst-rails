# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module TypstRails
  module Backends
    class GemTest < Minitest::Test
      def test_available_when_typst_gem_loaded
        require "typst"

        assert_predicate Gem.new, :available?
      end

      def test_compile_returns_real_pdf_bytes
        require "typst"

        backend = Gem.new

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Hello World")

          result = backend.compile(typ_path, dir)

          assert result.start_with?("%PDF")
        end
      end

      def test_compile_wraps_backend_errors
        backend = Gem.new

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Broken #nonexistent_function_call()")

          error = assert_raises(Error) { backend.compile(typ_path, dir) }
          assert_includes error.message, "Typst compilation failed"
        end
      end
    end
  end
end
