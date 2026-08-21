# frozen_string_literal: true

require "typst_rails/version"
require "typst_rails/renderer"
require "typst_rails/framework_detection"

# Conditionally load framework integrations
require "typst_rails/railtie" if TypstRails::FrameworkDetection.rails?

if TypstRails::FrameworkDetection.rage?
  require "typst_rails/rage_integration"
  TypstRails::RageIntegration.setup
end

if TypstRails::FrameworkDetection.sinatra?
  require "typst_rails/sinatra_integration"
  TypstRails::SinatraIntegration.setup
end

# Rails integration module for Typst document generation
#
# This module provides seamless integration of the Typst typesetting system
# with Ruby web applications. It supports Rails, Rage, Sinatra, and standalone
# Ruby usage through automatic framework detection.
#
# @example Basic configuration
#   TypstRails.configure do |config|
#     config.typst_executable_path = "/usr/local/bin/typst"
#     config.default_root_path = Rails.root.join("app", "assets", "typst")
#   end
#
# @example Standalone usage
#   renderer = TypstRails::Renderer.new("#let data = json(\"typst_data.json\")\n= #data.title")
#   pdf = renderer.render(nil, { title: "My Document" })
#   File.binwrite("output.pdf", pdf)
module TypstRails
  class << self
    # @return [Configuration] The current configuration instance
    attr_accessor :configuration
  end

  # Configures the Typst integration.
  #
  # This method yields a Configuration object for modification. If no
  # configuration exists, a new one is created with default values.
  #
  # @yield [configuration] Yields the configuration object for modification
  # @yieldparam configuration [Configuration] The configuration instance to modify
  # @return [Configuration] The configured instance
  # @raise [ArgumentError] if no block is given
  #
  # @example Configure Typst executable path
  #   TypstRails.configure do |config|
  #     config.typst_executable_path = "/opt/typst/bin/typst"
  #   end
  #
  # @example Configure default root path
  #   TypstRails.configure do |config|
  #     config.default_root_path = Rails.root.join("app", "typst")
  #   end
  def self.configure
    raise ArgumentError, "Block required for configuration" unless block_given?

    self.configuration ||= Configuration.new
    yield(configuration)
    configuration.validate!
    configuration
  end

  # Configuration class for Typst rendering options.
  #
  # This class holds configuration values that control how Typst documents
  # are compiled and rendered. It provides validation to ensure configuration
  # values are valid before use.
  #
  # @example Create and configure
  #   config = TypstRails::Configuration.new
  #   config.typst_executable_path = "/usr/local/bin/typst"
  #   config.validate! # Ensures configuration is valid
  class Configuration
    # @return [String] Path to the Typst executable (defaults to "typst" in PATH)
    attr_accessor :typst_executable_path

    # @return [String, nil] Default root path for Typst template resolution
    attr_accessor :default_root_path

    # Initializes a new Configuration with default values.
    #
    # Default values:
    # - `typst_executable_path`: "typst" (assumes typst is in PATH)
    # - `default_root_path`: nil (uses temporary directory)
    #
    # @return [Configuration] A new configuration instance
    #
    # @example Create configuration with defaults
    #   config = TypstRails::Configuration.new
    #   config.typst_executable_path #=> "typst"
    #   config.default_root_path #=> nil
    def initialize
      @typst_executable_path = "typst"
      @default_root_path = nil
    end

    # Validates the configuration settings.
    #
    # Ensures that:
    # - typst_executable_path is a non-empty string
    # - default_root_path (if set) is a valid directory path
    #
    # @return [true] if configuration is valid
    # @raise [ArgumentError] if typst_executable_path is invalid
    # @raise [ArgumentError] if default_root_path is invalid
    #
    # @example Validate configuration
    #   config = Configuration.new
    #   config.typst_executable_path = ""
    #   config.validate! # Raises ArgumentError
    def validate!
      if typst_executable_path.nil? || typst_executable_path.empty?
        raise ArgumentError, "typst_executable_path cannot be nil or empty"
      end

      unless typst_executable_path.is_a?(String)
        raise ArgumentError, "typst_executable_path must be a String"
      end

      if default_root_path && !default_root_path.is_a?(String)
        raise ArgumentError, "default_root_path must be a String or nil"
      end

      true
    end
  end
end
