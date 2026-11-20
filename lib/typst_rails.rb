# frozen_string_literal: true

require "typst_rails/version"
require "typst_rails/backends"
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
  # This method creates a new Configuration with default values and yields
  # it for modification. Each call replaces any previous configuration.
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
  #
  # @example Force a specific compilation backend
  #   TypstRails.configure do |config|
  #     config.backend = :gem # or :cli
  #   end
  def self.configure
    raise ArgumentError, "Block required for configuration" unless block_given?

    self.configuration = Configuration.new
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
    # PDF standards accepted by {#pdf_standard}, mapped to the identifiers the
    # Typst compiler uses for them (as listed by `typst compile --help`).
    PDF_STANDARDS = {
      pdf_1_4: "1.4",
      pdf_1_5: "1.5",
      pdf_1_6: "1.6",
      pdf_1_7: "1.7",
      pdf_2_0: "2.0",
      a_1a: "a-1a",
      a_1b: "a-1b",
      a_2a: "a-2a",
      a_2b: "a-2b",
      a_2u: "a-2u",
      a_3a: "a-3a",
      a_3b: "a-3b",
      a_3u: "a-3u",
      a_4: "a-4",
      a_4e: "a-4e",
      a_4f: "a-4f",
      ua_1: "ua-1"
    }.freeze

    # @return [String] Path to the Typst executable (defaults to "typst" in PATH)
    attr_accessor :typst_executable_path

    # @return [String, Pathname, nil] Typst root directory. When set, templates
    #   compile inside it, so they can load files beneath it with root-relative
    #   paths such as `image("/images/logo.png")`. The directory must be
    #   writable: each render creates a short-lived working directory in it.
    #   When nil, each render uses a private directory under Dir.tmpdir.
    attr_accessor :default_root_path

    # @return [Symbol, TypstRails::Backends::Base] Which compilation backend to use.
    #   `:auto` (the default) prefers the `typst` gem when installed, otherwise falls
    #   back to shelling out to the `typst` CLI. Set to `:gem` or `:cli` to force a
    #   specific built-in backend, or assign a custom backend instance registered
    #   via {TypstRails::Backends::Registry.register}.
    attr_accessor :backend

    # @return [Symbol, Array<Symbol>, nil] PDF standard(s) Typst should enforce
    #   conformance with, such as `:ua_1` for accessible PDF/UA-1 output or
    #   `[:a_2b, :ua_1]` for several at once. See {PDF_STANDARDS} for the
    #   accepted keys. When nil (the default), Typst writes a plain PDF.
    #   PDF/UA-1 requires the document to set a title with
    #   `#set document(title: ...)`; compilation fails without one.
    attr_accessor :pdf_standard

    # Initializes a new Configuration with default values.
    #
    # Default values:
    # - `typst_executable_path`: "typst" (assumes typst is in PATH)
    # - `default_root_path`: nil (each render gets a private temporary root)
    # - `backend`: `:auto` (prefer the `typst` gem, fall back to the CLI)
    # - `pdf_standard`: nil (plain PDF, no conformance enforced)
    #
    # @return [Configuration] A new configuration instance
    #
    # @example Create configuration with defaults
    #   config = TypstRails::Configuration.new
    #   config.typst_executable_path #=> "typst"
    #   config.default_root_path #=> nil
    #   config.backend #=> :auto
    def initialize
      @typst_executable_path = "typst"
      @default_root_path = nil
      @backend = :auto
      @pdf_standard = nil
    end

    # Options that backends pass through to the Typst compiler.
    #
    # @return [Hash{Symbol => Object}] compiler options:
    #   - `:pdf_standards` [Array<String>] Typst PDF standard identifiers
    #     (e.g. `["ua-1"]`), empty when {#pdf_standard} is nil
    # @raise [ArgumentError] if {#pdf_standard} contains an unknown key
    #
    # @example
    #   config = TypstRails::Configuration.new
    #   config.pdf_standard = [:a_2b, :ua_1]
    #   config.compile_options #=> { pdf_standards: ["a-2b", "ua-1"] }
    def compile_options
      { pdf_standards: pdf_standards }
    end

    # Validates the configuration settings.
    #
    # Ensures that:
    # - typst_executable_path is a non-empty string
    # - default_root_path (if set) is a String or Pathname
    # - pdf_standard (if set) is a key, or Array of keys, of {PDF_STANDARDS}
    #
    # @return [true] if configuration is valid
    # @raise [ArgumentError] if typst_executable_path is invalid
    # @raise [ArgumentError] if default_root_path is invalid
    # @raise [ArgumentError] if pdf_standard is invalid
    #
    # @example Validate configuration
    #   config = Configuration.new
    #   config.typst_executable_path = ""
    #   config.validate! # Raises ArgumentError
    def validate! # rubocop:disable Naming/PredicateMethod -- bang method raises, doesn't predicate
      raise ArgumentError, "typst_executable_path must be a String" unless typst_executable_path.is_a?(String)

      raise ArgumentError, "typst_executable_path cannot be nil or empty" if typst_executable_path.empty?

      if default_root_path && !default_root_path.is_a?(String) && !default_root_path.respond_to?(:to_path)
        raise ArgumentError, "default_root_path must be a String, Pathname, or nil"
      end

      pdf_standards
      true
    end

    private

    def pdf_standards
      Array(pdf_standard).map do |standard|
        PDF_STANDARDS.fetch(standard) do
          raise ArgumentError, "pdf_standard must be nil, or one or more of: " \
                               "#{PDF_STANDARDS.keys.map(&:inspect).join(", ")} (got #{standard.inspect})"
        end
      end.uniq
    end
  end
end
