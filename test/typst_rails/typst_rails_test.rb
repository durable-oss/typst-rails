# frozen_string_literal: true

require "English"
require "test_helper"

module TypstRails
  class TypstRailsTest < Minitest::Test
    def test_has_a_version_number
      assert TypstRails::VERSION
    end

    def test_configuration_requires_a_block
      assert_raises(ArgumentError, "Block required for configuration") do
        TypstRails.configure
      end
    end

    def test_configuration_validates_typst_executable_path_nil
      assert_raises(ArgumentError) do
        TypstRails.configure do |config|
          config.typst_executable_path = nil
        end
      end
    end

    def test_configuration_validates_typst_executable_path_empty
      assert_raises(ArgumentError) do
        TypstRails.configure do |config|
          config.typst_executable_path = ""
        end
      end
    end

    def test_configuration_validates_typst_executable_path_not_string
      assert_raises(ArgumentError) do
        TypstRails.configure do |config|
          config.typst_executable_path = 123
        end
      end
    end

    def test_configuration_validates_default_root_path_not_string
      assert_raises(ArgumentError) do
        TypstRails.configure do |config|
          config.default_root_path = 123
        end
      end
    end

    def test_configuration_allows_nil_default_root_path
      TypstRails.configure do |config|
        config.default_root_path = nil
      end
    end

    def test_configuration_allows_valid_string_default_root_path
      TypstRails.configure do |config|
        config.default_root_path = "/tmp"
      end
    end

    def test_configuration_accepts_valid_settings
      config = TypstRails.configure do |c|
        c.typst_executable_path = "/usr/bin/typst"
        c.default_root_path = "/app/typst"
      end

      assert_equal "/usr/bin/typst", config.typst_executable_path
      assert_equal "/app/typst", config.default_root_path
    end

    def test_configuration_has_sensible_defaults
      config = TypstRails::Configuration.new

      assert_equal "typst", config.typst_executable_path
      assert_nil config.default_root_path
    end

    def test_defines_symbolize_keys_shim_when_active_support_unavailable
      run_subprocess_check("without_active_support_check.rb")
    end

    def test_requires_and_sets_up_rage_integration_when_rage_defined_at_load_time
      run_subprocess_check("framework_autoload_check.rb", "rage")
    end

    def test_requires_and_sets_up_sinatra_integration_when_sinatra_defined_at_load_time
      run_subprocess_check("framework_autoload_check.rb", "sinatra")
    end

    def test_renderer_compiles_when_only_renderer_is_required_without_configuration
      run_subprocess_check("renderer_standalone_check.rb")
    end

    private

    def run_subprocess_check(script_name, *args)
      script = File.expand_path("../support/#{script_name}", __dir__)
      lib_dir = File.expand_path("../../lib", __dir__)

      output = IO.popen([RbConfig.ruby, "-I", lib_dir, script, *args], &:read)

      assert_predicate $CHILD_STATUS, :success?, "Expected #{script_name} to exit successfully, got:\n#{output}"
      assert_equal "OK", output.lines.last&.strip, "Expected #{script_name} to print OK, got:\n#{output}"
    end
  end
end
