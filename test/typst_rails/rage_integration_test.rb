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
  end
end
