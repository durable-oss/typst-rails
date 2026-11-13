# frozen_string_literal: true

require "test_helper"
require "typst_rails/rage_integration"

module TypstRails
  class RageIntegrationTest < Minitest::Test
    # MARK: - setup

    def test_setup_returns_without_error_when_rage_not_defined
      with_undefined_constant(:Rage) do
        assert_nil RageIntegration.setup
      end
    end

    def test_setup_adds_render_typst_to_rage_controllers
      controller = fake_rage_controller

      with_fake_rage(controller) { RageIntegration.setup }

      assert_includes controller, RageIntegration::ControllerHelpers
      assert controller.method_defined?(:render_typst)
    end

    def test_setup_is_idempotent
      controller = fake_rage_controller

      with_fake_rage(controller) do
        RageIntegration.setup
        RageIntegration.setup
      end

      assert_equal 1, controller.ancestors.count(RageIntegration::ControllerHelpers)
    end

    # Rage may be detected before its controllers load; setup must not fail.
    def test_setup_without_rage_controller_is_a_no_op
      with_defined_constant(:Rage, Module.new) do
        with_undefined_constant(:RageController) do
          assert_nil RageIntegration.setup
        end
      end
    end

    # MARK: - render_typst

    def test_render_typst_responds_with_the_pdf
      template_file = create_temp_typst_file("= Report")
      mock_successful_typst_compilation(pdf_content: "rage pdf")

      controller = build_controller
      controller.render_typst(template_file.path)

      assert_equal "rage pdf", controller.rendered[:plain]
      assert_equal "application/pdf", controller.headers["content-type"]
    ensure
      template_file&.unlink
    end

    def test_render_typst_passes_the_status
      template_file = create_temp_typst_file("= Report")
      mock_successful_typst_compilation

      controller = build_controller
      controller.render_typst(template_file.path, {}, status: :created)

      assert_equal :created, controller.rendered[:status]
    ensure
      template_file&.unlink
    end

    def test_render_typst_runs_erb_in_the_controller_scope
      template_file = create_temp_typst_file("= <%= @title %>: <%= escape_typst(note) %>")
      captured = capture_rendered_source

      controller = build_controller
      controller.instance_variable_set(:@title, "Report")
      controller.render_typst(template_file.path, { note: "#1" })

      assert_equal "= Report: \\#1", captured.call
    ensure
      template_file&.unlink
    end

    def test_render_typst_writes_locals_to_the_data_file
      template_file = create_temp_typst_file('#let data = json("typst_data.json")')
      data = nil
      backend = stub("backend")
      backend.stubs(:compile).with do |typ_path, _root|
        data = JSON.parse(File.read(File.join(File.dirname(typ_path), "typst_data.json")))
      end.returns("pdf")
      Backends::Registry.stubs(:resolve).returns(backend)

      build_controller.render_typst(template_file.path, { total: 42 })

      assert_equal({ "total" => 42 }, data)
    ensure
      template_file&.unlink
    end

    private

    # A stand-in for RageController::API with the parts render_typst uses.
    # Like Rage, render(plain:) sets a text/plain content type.
    def fake_rage_controller
      Class.new do
        attr_reader :rendered

        def headers
          @headers ||= {}
        end

        def render(plain: nil, status: nil)
          @rendered = { plain: plain, status: status }
          headers["content-type"] = "text/plain; charset=utf-8"
        end
      end
    end

    def build_controller
      controller = fake_rage_controller
      controller.include(RageIntegration::ControllerHelpers)
      controller.new
    end

    def with_fake_rage(controller, &block)
      rage_controller = Module.new
      rage_controller.const_set(:API, controller)

      with_defined_constant(:Rage, Module.new) do
        with_defined_constant(:RageController, rage_controller, &block)
      end
    end

    # Stubs the Renderer and returns a lambda yielding the source it got.
    def capture_rendered_source
      captured = nil
      renderer = mock("renderer")
      renderer.stubs(:render).returns("pdf")
      Renderer.stubs(:new).with { |src| captured = src }.returns(renderer)
      -> { captured }
    end
  end
end
