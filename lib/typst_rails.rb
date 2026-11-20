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

    # @return [Array<String, Pathname>] Extra directories Typst searches,
    #   recursively, for font files. Defaults to an empty list. Assigning a
    #   single path wraps it in an Array. Relative paths are expanded against
    #   the process working directory when a document is compiled.
    attr_reader :font_paths

    # @return [Boolean] Whether Typst should skip the fonts installed on the
    #   system and use only {#font_paths} plus the fonts embedded in Typst.
    #   Defaults to false.
    attr_accessor :ignore_system_fonts

    # @return [#call, nil] Called with `(warnings, template)` after a
    #   successful compile that produced warnings: an array of
    #   {TypstRails::Diagnostics::Diagnostic} and the template's display name
    #   (or nil). The default logs them through Rails.logger.warn when Rails
    #   is loaded, and Kernel#warn otherwise. Set to nil to ignore warnings.
    #   Only the `:cli` backend reports warnings from successful compiles;
    #   the `typst` gem does not expose them.
    attr_accessor :on_warning

    # Initializes a new Configuration with default values.
    #
    # Default values:
    # - `typst_executable_path`: "typst" (assumes typst is in PATH)
    # - `default_root_path`: nil (each render gets a private temporary root)
    # - `backend`: `:auto` (prefer the `typst` gem, fall back to the CLI)
    # - `pdf_standard`: nil (plain PDF, no conformance enforced)
    # - `font_paths`: [] (no extra font directories)
    # - `ignore_system_fonts`: false (system fonts are searched)
    # - `on_warning`: logs warnings (see {TypstRails::Diagnostics.log_warnings})
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
      @font_paths = []
      @ignore_system_fonts = false
      @on_warning = Diagnostics.method(:log_warnings)
    end

    # Sets the font directories. A single String or Pathname is wrapped in an
    # Array, and nil clears the list.
    #
    # @param paths [Array<String, Pathname>, String, Pathname, nil]
    # @return [void]
    #
    # @example
    #   config.font_paths = Rails.root.join("app", "assets", "fonts")
    #   config.font_paths #=> [#<Pathname:/app/app/assets/fonts>]
    def font_paths=(paths)
      @font_paths = paths.is_a?(Array) ? paths : Array(paths)
    end

    # Options that backends pass through to the Typst compiler.
    #
    # @return [Hash{Symbol => Object}] compiler options:
    #   - `:pdf_standards` [Array<String>] Typst PDF standard identifiers
    #     (e.g. `["ua-1"]`), empty when {#pdf_standard} is nil
    #   - `:font_paths` [Array<String>] font directories, expanded to absolute paths
    #   - `:ignore_system_fonts` [Boolean]
    # @raise [ArgumentError] if {#pdf_standard} contains an unknown key
    #
    # @example
    #   config = TypstRails::Configuration.new
    #   config.pdf_standard = :ua_1
    #   config.font_paths = ["vendor/fonts"]
    #   config.compile_options
    #   #=> { pdf_standards: ["ua-1"], font_paths: ["/app/vendor/fonts"], ignore_system_fonts: false }
    def compile_options
      {
        pdf_standards: pdf_standards,
        font_paths: font_paths.map { |path| File.expand_path(path) },
        ignore_system_fonts: ignore_system_fonts
      }
    end

    # Validates the configuration settings.
    #
    # Ensures that:
    # - typst_executable_path is a non-empty string
    # - default_root_path (if set) is a String or Pathname
    # - pdf_standard (if set) is a key, or Array of keys, of {PDF_STANDARDS}
    # - font_paths is an Array of Strings or Pathnames
    # - ignore_system_fonts is true or false
    # - on_warning (if set) responds to #call
    #
    # @return [true] if configuration is valid
    # @raise [ArgumentError] if typst_executable_path is invalid
    # @raise [ArgumentError] if default_root_path is invalid
    # @raise [ArgumentError] if pdf_standard is invalid
    # @raise [ArgumentError] if font_paths or ignore_system_fonts is invalid
    # @raise [ArgumentError] if on_warning is not callable
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
      validate_font_options!
      raise ArgumentError, "on_warning must respond to #call, or be nil" if on_warning && !on_warning.respond_to?(:call)

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

    def validate_font_options!
      unless font_paths.is_a?(Array) && font_paths.all? { |path| path_like?(path) }
        raise ArgumentError, "font_paths must be an Array of Strings or Pathnames"
      end

      return if [true, false].include?(ignore_system_fonts)

      raise ArgumentError, "ignore_system_fonts must be true or false"
    end

    def path_like?(path)
      (path.is_a?(String) && !path.empty?) || path.respond_to?(:to_path)
    end
  end
end
