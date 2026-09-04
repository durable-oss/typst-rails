# frozen_string_literal: true

require "test_helper"
require "typst_rails/rage_integration"

module TypstRails
  class RageIntegrationTest < Minitest::Test
    def test_setup_returns_without_error_when_rage_not_defined
      with_undefined_constant(:Rage) do
        assert_nil RageIntegration.setup
      end
    end

    def test_setup_configures_rage_when_rage_defined
      rage_module = Module.new
      configured = false
      rage_module.define_singleton_method(:configure) do |&block|
        configured = true
        block.call(nil)
      end

      with_defined_constant(:Rage, rage_module) do
        RageIntegration.setup
      end

      assert configured, "Expected Rage.configure to be called"
    end

    # Setup is a no-op guard plus a Rage.configure call; the guard is what
    # keeps `require "typst_rails"` safe in a non-Rage process.
    def test_setup_does_not_call_configure_when_rage_is_undefined
      with_undefined_constant(:Rage) do
        # No Rage constant exists, so nothing can be configured; reaching this
        # without a NameError is the assertion.
        assert_nil RageIntegration.setup
      end
    end

    def test_setup_requires_the_renderer
      rage_module = Module.new
      rage_module.define_singleton_method(:configure) { |&block| block.call(nil) }

      with_defined_constant(:Rage, rage_module) do
        RageIntegration.setup
      end

      assert defined?(TypstRails::Renderer), "setup should make the Renderer available"
    end

    def test_setup_yields_to_the_configure_block
      rage_module = Module.new
      yielded = false
      rage_module.define_singleton_method(:configure) do |&block|
        block.call(nil)
        yielded = true
      end

      with_defined_constant(:Rage, rage_module) do
        RageIntegration.setup
      end

      assert yielded, "the block passed to Rage.configure should run to completion"
    end

    def test_setup_is_idempotent
      rage_module = Module.new
      calls = 0
      rage_module.define_singleton_method(:configure) do |&block|
        calls += 1
        block.call(nil)
      end

      with_defined_constant(:Rage, rage_module) do
        RageIntegration.setup
        RageIntegration.setup
      end

      assert_equal 2, calls, "each setup call should reach Rage.configure"
    end

    # A Rage that raises from configure must surface the error rather than
    # being swallowed at require time.
    def test_setup_propagates_errors_from_configure
      rage_module = Module.new
      rage_module.define_singleton_method(:configure) { |&_block| raise "rage boom" }

      with_defined_constant(:Rage, rage_module) do
        error = assert_raises(RuntimeError) { RageIntegration.setup }

        assert_equal "rage boom", error.message
      end
    end
  end
end
