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
  end
end
