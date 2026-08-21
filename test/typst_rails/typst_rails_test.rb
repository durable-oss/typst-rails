# frozen_string_literal: true

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
      assert_nothing_raised do
        TypstRails.configure do |config|
          config.default_root_path = nil
        end
      end
    end

    def test_configuration_allows_valid_string_default_root_path
      assert_nothing_raised do
        TypstRails.configure do |config|
          config.default_root_path = "/tmp"
        end
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
  end
end
