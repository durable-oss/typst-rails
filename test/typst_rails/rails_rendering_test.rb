# frozen_string_literal: true

require "test_helper"

module TypstRails
  # Rails is not in the bundle, so these tests stand up ActionController::Base
  # and ApplicationController stand-ins. The real thing was checked by hand
  # against a Rails app outside the repository.
  class RailsRenderingTest < Minitest::Test
    class FakeAttachable
      attr_reader :attached

      def attach(io:, filename:, content_type:)
        @attached = { body: io.read, filename: filename, content_type: content_type }
      end
    end

    # A controller class whose .render records its arguments and returns a
    # fixed body.
    def fake_controller(body = "%PDF-fake".b, superclass = Object)
      klass = Class.new(superclass) do
        class << self
          attr_accessor :rendered_with, :body
        end

        def self.render(**options)
          self.rendered_with = options
          body
        end
      end
      klass.body = body
      klass
    end

    # Defines ActionController::Base (and ::API) for the block. Yields the
    # Base class.
    def with_action_controller
      base = fake_controller
      api = Class.new
      action_controller = Module.new
      action_controller.const_set(:Base, base)
      action_controller.const_set(:API, api)

      with_defined_constant(:ActionController, action_controller) { yield base, api }
    end

    # MARK: - Without ActionController

    def test_raises_a_typst_error_without_action_controller
      with_undefined_constant(:ActionController) do
        error = assert_raises(Error) { TypstRails.render_with_rails("reports/monthly") }

        assert_equal "render_with_rails requires ActionController; use TypstRails.render", error.message
      end
    end

    def test_is_defined_without_rails
      assert_respond_to TypstRails, :render_with_rails
    end

    # MARK: - Controller selection

    def test_defaults_to_action_controller_base_without_application_controller
      with_action_controller do |base, _api|
        with_undefined_constant(:ApplicationController) do
          TypstRails.render_with_rails("reports/monthly")
        end

        refute_nil base.rendered_with
      end
    end

    def test_prefers_application_controller_when_it_inherits_from_base
      with_action_controller do |base, _api|
        app_controller = fake_controller("%PDF-app".b, base)

        with_defined_constant(:ApplicationController, app_controller) do
          assert_equal "%PDF-app", TypstRails.render_with_rails("reports/monthly")
        end
        assert_nil base.rendered_with
      end
    end

    def test_skips_an_api_application_controller
      with_action_controller do |base, api|
        with_defined_constant(:ApplicationController, fake_controller("api".b, api)) do
          TypstRails.render_with_rails("reports/monthly")
        end

        refute_nil base.rendered_with
      end
    end

    def test_skips_an_application_controller_that_is_not_a_class
      with_action_controller do |base, _api|
        with_defined_constant(:ApplicationController, Module.new) do
          TypstRails.render_with_rails("reports/monthly")
        end

        refute_nil base.rendered_with
      end
    end

    def test_uses_the_given_controller
      with_action_controller do |base, _api|
        admin = fake_controller("%PDF-admin".b)

        assert_equal "%PDF-admin", TypstRails.render_with_rails("reports/monthly", controller: admin)
        assert_nil base.rendered_with
      end
    end

    # MARK: - Arguments and result

    def test_passes_template_pdf_format_locals_and_assigns
      with_action_controller do |_base, _api|
        controller = fake_controller

        TypstRails.render_with_rails(:"reports/monthly", controller: controller,
                                                         locals: { month: "October" }, assigns: { title: "T" })

        assert_equal({ template: "reports/monthly", formats: [:pdf],
                       locals: { month: "October" }, assigns: { title: "T" } },
                     controller.rendered_with)
      end
    end

    def test_returns_a_plain_binary_string
      buffer_class = Class.new(String)
      body = buffer_class.new("%PDF-\xE2\x80\x94".dup.force_encoding(Encoding::UTF_8))

      with_action_controller do |_base, _api|
        pdf = TypstRails.render_with_rails("r", controller: fake_controller(body))

        assert_instance_of String, pdf
        assert_equal Encoding::BINARY, pdf.encoding
        assert_equal "%PDF-\xE2\x80\x94".b, pdf
      end
    end

    # ActionView::OutputBuffer is not a String subclass on Rails 7.1+.
    def test_converts_a_non_string_buffer
      buffer = Struct.new(:content) do
        def to_s
          content
        end
      end.new("%PDF-buffer")

      with_action_controller do |_base, _api|
        assert_equal "%PDF-buffer".b, TypstRails.render_with_rails("r", controller: fake_controller(buffer))
      end
    end

    def test_rejects_non_hash_locals_and_assigns
      assert_raises(ArgumentError) { TypstRails.render_with_rails("r", locals: []) }
      assert_raises(ArgumentError) { TypstRails.render_with_rails("r", assigns: nil) }
    end

    # MARK: - render_and_attach via: :rails

    def test_render_and_attach_via_rails
      attachable = FakeAttachable.new

      with_action_controller do |_base, _api|
        controller = fake_controller("%PDF-rails".b)

        TypstRails.render_and_attach(attachable, "reports/monthly",
                                     filename: "m.pdf", via: :rails, controller: controller,
                                     locals: { a: 1 }, assigns: { b: 2 })

        assert_equal({ a: 1 }, controller.rendered_with[:locals])
        assert_equal({ b: 2 }, controller.rendered_with[:assigns])
      end
      assert_equal({ body: "%PDF-rails", filename: "m.pdf", content_type: "application/pdf" }, attachable.attached)
    end

    def test_render_and_attach_rejects_an_unknown_via
      error = assert_raises(ArgumentError) do
        TypstRails.render_and_attach(FakeAttachable.new, "r", filename: "x.pdf", via: :erb)
      end

      assert_match(/via must be/, error.message)
    end
  end
end
