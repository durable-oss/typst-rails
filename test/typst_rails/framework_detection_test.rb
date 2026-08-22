# frozen_string_literal: true

require "test_helper"

module TypstRails
  class FrameworkDetectionTest < Minitest::Test
    def test_rails_detection_when_rails_defined
      with_defined_constant(:Rails, mock_rails_class) do
        assert_predicate FrameworkDetection, :rails?, "Should detect Rails when Rails constant is defined"
      end
    end

    def test_rails_detection_when_rails_not_defined
      with_undefined_constant(:Rails) do
        refute_predicate FrameworkDetection, :rails?, "Should not detect Rails when Rails constant is not defined"
      end
    end

    def test_rails_detection_when_rails_lacks_application_method
      rails_without_application = Class.new

      with_defined_constant(:Rails, rails_without_application) do
        refute_predicate FrameworkDetection, :rails?, "Should not detect Rails when Rails.application is not available"
      end
    end

    def test_rage_detection_when_rage_defined
      with_defined_constant(:Rage, Module.new) do
        with_defined_constant(:Rage, Module.new.tap { |m| m.const_set(:Application, Class.new) }) do
          assert_predicate FrameworkDetection, :rage?, "Should detect Rage when Rage::Application is defined"
        end
      end
    end

    def test_rage_detection_when_rage_not_defined
      with_undefined_constant(:Rage) do
        refute_predicate FrameworkDetection, :rage?, "Should not detect Rage when Rage constant is not defined"
      end
    end

    def test_sinatra_detection_when_sinatra_defined
      with_defined_constant(:Sinatra, Module.new) do
        sinatra_module = Module.new
        sinatra_module.const_set(:Base, Class.new)

        with_defined_constant(:Sinatra, sinatra_module) do
          assert_predicate FrameworkDetection, :sinatra?, "Should detect Sinatra when Sinatra::Base is defined"
        end
      end
    end

    def test_sinatra_detection_when_sinatra_not_defined
      with_undefined_constant(:Sinatra) do
        refute_predicate FrameworkDetection, :sinatra?, "Should not detect Sinatra when Sinatra constant is not defined"
      end
    end

    def test_detected_framework_returns_rails
      with_defined_constant(:Rails, mock_rails_class) do
        assert_equal :rails, FrameworkDetection.detected_framework
      end
    end

    def test_detected_framework_returns_rage_when_no_rails
      with_undefined_constant(:Rails) do
        rage_module = Module.new
        rage_module.const_set(:Application, Class.new)

        with_defined_constant(:Rage, rage_module) do
          assert_equal :rage, FrameworkDetection.detected_framework
        end
      end
    end

    def test_detected_framework_returns_sinatra_when_no_rails_or_rage
      with_undefined_constant(:Rails) do
        with_undefined_constant(:Rage) do
          sinatra_module = Module.new
          sinatra_module.const_set(:Base, Class.new)

          with_defined_constant(:Sinatra, sinatra_module) do
            assert_equal :sinatra, FrameworkDetection.detected_framework
          end
        end
      end
    end

    def test_detected_framework_returns_nil_when_no_framework
      with_undefined_constant(:Rails) do
        with_undefined_constant(:Rage) do
          with_undefined_constant(:Sinatra) do
            assert_nil FrameworkDetection.detected_framework
          end
        end
      end
    end

    def test_framework_priority_rails_over_rage
      rails_class = mock_rails_class
      rage_module = Module.new
      rage_module.const_set(:Application, Class.new)

      with_defined_constant(:Rails, rails_class) do
        with_defined_constant(:Rage, rage_module) do
          assert_equal :rails, FrameworkDetection.detected_framework,
                       "Rails should take priority over Rage"
        end
      end
    end

    def test_framework_priority_rage_over_sinatra
      with_undefined_constant(:Rails) do
        rage_module = Module.new
        rage_module.const_set(:Application, Class.new)
        sinatra_module = Module.new
        sinatra_module.const_set(:Base, Class.new)

        with_defined_constant(:Rage, rage_module) do
          with_defined_constant(:Sinatra, sinatra_module) do
            assert_equal :rage, FrameworkDetection.detected_framework,
                         "Rage should take priority over Sinatra"
          end
        end
      end
    end

    private

    def mock_rails_class
      rails = Class.new
      rails.define_singleton_method(:application) { true }
      rails.define_singleton_method(:respond_to?) { |method| method == :application }
      rails
    end
  end
end
