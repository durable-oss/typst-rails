# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module TypstRails
  module Backends
    class GemTest < Minitest::Test
      # The `typst` gem requires Ruby >= 3.0, so it is not a development
      # dependency on 2.7. Tests that compile for real skip there rather than
      # erroring; #available? is still covered in both directions below.
      TYPST_GEM_INSTALLED = begin
        require "typst"
        true
      rescue LoadError
        false
      end

      def setup
        skip "the typst gem is not installed on Ruby #{RUBY_VERSION}" unless TYPST_GEM_INSTALLED
      end

      def test_available_when_typst_gem_loaded
        assert_predicate Gem.new, :available?
      end

      def test_compile_returns_real_pdf_bytes
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
