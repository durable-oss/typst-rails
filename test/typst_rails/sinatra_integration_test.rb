# frozen_string_literal: true

require "test_helper"
require "typst_rails/sinatra_integration"

module TypstRails
  class SinatraIntegrationTest < Minitest::Test
    def test_setup_returns_without_error_when_sinatra_not_defined
      with_undefined_constant(:Sinatra) do
        assert_nil SinatraIntegration.setup
      end
    end

    def test_setup_defines_typst_helper_on_sinatra_base
      sinatra_module = Module.new
      base_class = Class.new
      sinatra_module.const_set(:Base, base_class)

      with_defined_constant(:Sinatra, sinatra_module) do
        SinatraIntegration.setup
      end

      assert base_class.method_defined?(:typst), "Expected Sinatra::Base to define #typst"
    end

    def test_typst_helper_renders_pdf_with_content_type
      sinatra_module = Module.new
      base_class = Class.new do
        attr_reader :content_type_set

        def content_type(type)
          @content_type_set = type
        end
      end
      sinatra_module.const_set(:Base, base_class)

      with_defined_constant(:Sinatra, sinatra_module) do
        SinatraIntegration.setup
      end

      template_file = create_temp_typst_file("= Test")
      mock_successful_typst_compilation(pdf_content: "sinatra pdf")

      instance = base_class.new
      pdf = instance.typst(template_file.path, { title: "Report" })

      assert_equal "application/pdf", instance.content_type_set
      assert_equal "sinatra pdf", pdf
    ensure
      template_file&.unlink
    end
    # MARK: - ViewContext

    # Renderer calls #assigns on whatever view context it is handed; the
    # Struct exists purely to satisfy that interface for Sinatra.
    def test_view_context_exposes_assigns
      context = SinatraIntegration::ViewContext.new({ title: "Report" })

      assert_equal({ title: "Report" }, context.assigns)
    end

    def test_view_context_accepts_empty_assigns
      assert_empty SinatraIntegration::ViewContext.new({}).assigns
    end

    def test_view_context_responds_to_assigns
      assert_respond_to SinatraIntegration::ViewContext.new({}), :assigns
    end

    # MARK: - #typst helper

    def test_typst_helper_reads_the_template_from_disk
      base_class = setup_fake_sinatra
      template_file = create_temp_typst_file("= From Disk")
      captured = nil

      force_cli_backend!
      Renderer.expects(:new).with { |src| captured = src }.returns(
        mock("renderer").tap { |r| r.expects(:render).returns("pdf") }
      )

      base_class.new.typst(template_file.path)

      assert_equal "= From Disk", captured
    ensure
      template_file&.unlink
    end

    # Locals are handed to the renderer both as the view context's assigns and
    # as local_assigns, matching how Rails supplies each.
    def test_typst_helper_passes_locals_as_both_assigns_and_local_assigns
      base_class = setup_fake_sinatra
      template_file = create_temp_typst_file("= Test")
      locals = { title: "Report" }
      captured_context = nil

      Renderer.expects(:new).returns(
        mock("renderer").tap do |r|
          r.expects(:render).with do |context, local_assigns|
            captured_context = context
            local_assigns == locals
          end.returns("pdf")
        end
      )

      base_class.new.typst(template_file.path, locals)

      assert_equal locals, captured_context.assigns
    ensure
      template_file&.unlink
    end

    def test_typst_helper_defaults_locals_to_an_empty_hash
      base_class = setup_fake_sinatra
      template_file = create_temp_typst_file("= Test")

      Renderer.expects(:new).returns(
        mock("renderer").tap { |r| r.expects(:render).with(anything, {}).returns("pdf") }
      )

      base_class.new.typst(template_file.path)
    ensure
      template_file&.unlink
    end

    # The third argument is accepted for API compatibility and ignored.
    def test_typst_helper_ignores_the_options_argument
      base_class = setup_fake_sinatra
      template_file = create_temp_typst_file("= Test")
      mock_successful_typst_compilation(pdf_content: "pdf")

      assert_equal "pdf", base_class.new.typst(template_file.path, {}, { layout: false })
    ensure
      template_file&.unlink
    end

    def test_typst_helper_propagates_a_missing_template_error
      base_class = setup_fake_sinatra

      assert_raises(Errno::ENOENT) { base_class.new.typst("/no/such/template.typ") }
    end

    def test_typst_helper_propagates_compilation_errors
      base_class = setup_fake_sinatra
      template_file = create_temp_typst_file("= Test")
      mock_failed_typst_compilation(stderr: "syntax error")

      assert_raises(Error) { base_class.new.typst(template_file.path) }
    ensure
      template_file&.unlink
    end

    def test_setup_is_idempotent
      base_class = setup_fake_sinatra
      sinatra_module = Module.new
      sinatra_module.const_set(:Base, base_class)

      with_defined_constant(:Sinatra, sinatra_module) do
        SinatraIntegration.setup
        SinatraIntegration.setup
      end

      assert base_class.method_defined?(:typst)
    end

    private

    # Builds a fake Sinatra::Base with the #content_type hook the helper calls,
    # runs setup against it, and returns the class.
    def setup_fake_sinatra
      base_class = Class.new do
        attr_reader :content_type_set

        def content_type(type)
          @content_type_set = type
        end
      end
      sinatra_module = Module.new
      sinatra_module.const_set(:Base, base_class)

      with_defined_constant(:Sinatra, sinatra_module) { SinatraIntegration.setup }

      base_class
    end
  end
end
