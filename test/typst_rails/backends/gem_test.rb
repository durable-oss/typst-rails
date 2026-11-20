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

      # MARK: - PDF standards

      def test_compile_passes_pdf_standards_to_the_gem
        TypstRails.configure { |c| c.pdf_standard = %i[a_2b ua_1] }

        assert_equal %w[a-2b ua-1], capture_gem_options[:pdf_standards]
      ensure
        TypstRails.configuration = nil
      end

      # With no standard set, only file and root are passed, as before.
      def test_compile_omits_pdf_standards_by_default
        TypstRails.configure { |c| c.backend = :gem }

        refute capture_gem_options.key?(:pdf_standards)
      ensure
        TypstRails.configuration = nil
      end

      def test_compile_omits_pdf_standards_without_configuration
        TypstRails.configuration = nil

        assert_equal %i[file root], capture_gem_options.keys
      end

      def test_compile_produces_a_pdf_ua_document_with_the_real_gem
        requires_typst_gem!
        TypstRails.configure { |c| c.pdf_standard = :ua_1 }

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "#set document(title: \"Accessible report\")\n= Hello\n\nBody text.\n")

          pdf = Gem.new.compile(typ_path, dir)

          assert pdf.start_with?("%PDF")
          assert_includes pdf, "pdfuaid"
        end
      ensure
        TypstRails.configuration = nil
      end

      def test_real_gem_rejects_a_pdf_ua_document_without_a_title
        requires_typst_gem!
        TypstRails.configure { |c| c.pdf_standard = :ua_1 }

        Dir.mktmpdir do |dir|
          typ_path = File.join(dir, "doc.typ")
          File.write(typ_path, "= Hello\n")

          error = assert_raises(Error) { Gem.new.compile(typ_path, dir) }

          assert_includes error.message, "missing document title"
        end
      ensure
        TypstRails.configuration = nil
      end

      private

      # Compiles against a stand-in Typst::Pdf and returns the options it got.
      def capture_gem_options
        captured = {}
        pdf_class = Class.new do
          define_method(:initialize) { |**options| captured.replace(options) }

          def compiled
            self
          end

          def document
            "%PDF-fake"
          end
        end

        with_defined_constant(:Typst, Module.new { const_set(:Pdf, pdf_class) }) do
          Gem.new.compile("/tmp/doc.typ", "/tmp")
        end

        captured
      end
    end
  end
end
