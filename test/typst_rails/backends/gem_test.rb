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

      # Guards only the tests that need a working compiler. #available? and the
      # error-wrapping paths are exercised on every Ruby, gem or no gem.
      def requires_typst_gem!
        return if TYPST_GEM_INSTALLED

        skip "the typst gem is not installed on Ruby #{RUBY_VERSION}"
      end

      def test_available_when_typst_gem_loaded
        requires_typst_gem!

        assert_predicate Gem.new, :available?
      end

      def test_compile_returns_real_pdf_bytes
        requires_typst_gem!
        backend = Gem.new

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Hello World")

          result = backend.compile(typ_path, dir)

          assert result.start_with?("%PDF")
        end
      end

      def test_compile_wraps_backend_errors
        requires_typst_gem!
        backend = Gem.new

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Broken #nonexistent_function_call()")

          error = assert_raises(Error) { backend.compile(typ_path, dir) }
          assert_includes error.message, "Typst compilation failed"
        end
      end
      # MARK: - Availability detection (runs with or without the gem present)

      # The happy path short-circuits on the already-loaded constant rather
      # than paying for a require on every call.
      def test_available_short_circuits_when_typst_pdf_is_already_defined
        backend = Gem.new
        backend.expects(:require).never

        with_defined_constant(:Typst, Module.new { const_set(:Pdf, Class.new) }) do
          assert_predicate backend, :available?
        end
      end

      def test_not_available_when_the_typst_gem_cannot_be_loaded
        backend = Gem.new
        backend.stubs(:require).with("typst").raises(LoadError, "cannot load such file -- typst")

        with_undefined_constant(:Typst) do
          refute_predicate backend, :available?
        end
      end

      # A LoadError must be swallowed into `false`, never propagated: an absent
      # optional backend is a normal condition that auto-detection handles.
      def test_load_error_does_not_escape_available
        backend = Gem.new
        backend.stubs(:require).with("typst").raises(LoadError, "boom")

        with_undefined_constant(:Typst) do
          assert_same false, backend.available?,
                      "a missing optional backend must report false, not raise or return nil"
        end
      end

      def test_available_returns_true_when_the_require_succeeds
        backend = Gem.new
        backend.stubs(:require).with("typst").returns(true)

        with_undefined_constant(:Typst) do
          assert_predicate backend, :available?
        end
      end

      # MARK: - Error wrapping (no real gem required)

      # Whatever the native extension raises must surface as TypstRails::Error
      # so callers can rescue one error class across both backends.
      def test_compile_wraps_arbitrary_backend_exceptions_in_typst_rails_error
        backend = Gem.new
        pdf_class = Class.new do
          def initialize(*)
            raise "native extension exploded"
          end
        end

        with_defined_constant(:Typst, Module.new { const_set(:Pdf, pdf_class) }) do
          error = assert_raises(Error) { backend.compile("/tmp/doc.typ", "/tmp") }

          assert_includes error.message, "Typst compilation failed"
          assert_includes error.message, "native extension exploded"
        end
      end

      def test_compile_passes_file_and_root_through_to_the_gem
        backend = Gem.new
        captured = {}
        pdf_class = Class.new do
          define_method(:initialize) do |file:, root:|
            captured[:file] = file
            captured[:root] = root
          end

          def compiled
            self
          end

          def document
            "%PDF-fake"
          end
        end

        with_defined_constant(:Typst, Module.new { const_set(:Pdf, pdf_class) }) do
          assert_equal "%PDF-fake", backend.compile("/tmp/doc.typ", "/tmp")
        end

        assert_equal "/tmp/doc.typ", captured[:file]
        assert_equal "/tmp", captured[:root]
      end
    end
  end
end
