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

    # Regression: Cli#executable_path read TypstRails.configuration without
    # checking that the top-level module was loaded, so the :cli backend raised
    # NoMethodError under a bare `require "typst_rails/renderer"`. It went
    # unnoticed because the :gem backend is picked first wherever the typst gem
    # is installed, leaving Cli#available? uncalled.
    def test_cli_backend_works_when_only_renderer_is_required_without_configuration
      run_subprocess_check("cli_backend_standalone_check.rb")
    end

    # MARK: - Configuration lifecycle

    # Each configure call builds a fresh Configuration rather than mutating the
    # previous one, so settings do not accumulate across calls.
    def test_configure_replaces_rather_than_merges_previous_configuration
      TypstRails.configure do |config|
        config.typst_executable_path = "/first/typst"
        config.default_root_path = "/first/root"
      end

      TypstRails.configure { |config| config.typst_executable_path = "/second/typst" }

      assert_equal "/second/typst", TypstRails.configuration.typst_executable_path
      assert_nil TypstRails.configuration.default_root_path,
                 "a second configure call should start from defaults, not carry the previous root path"
    ensure
      TypstRails.configuration = nil
    end

    def test_configure_returns_the_configuration
      result = TypstRails.configure { |config| config.typst_executable_path = "typst" }

      assert_same TypstRails.configuration, result
    ensure
      TypstRails.configuration = nil
    end

    def test_configuration_is_readable_and_writable
      config = TypstRails::Configuration.new
      TypstRails.configuration = config

      assert_same config, TypstRails.configuration
    ensure
      TypstRails.configuration = nil
    end

    # A validation failure must not install a half-configured object, or the
    # next render would run against invalid settings.
    def test_invalid_configuration_still_raises_from_configure
      assert_raises(ArgumentError) do
        TypstRails.configure { |config| config.typst_executable_path = "" }
      end
    ensure
      TypstRails.configuration = nil
    end

    # MARK: - backend setting

    def test_backend_defaults_to_auto
      assert_equal :auto, TypstRails::Configuration.new.backend
    end

    def test_backend_accepts_a_symbol
      TypstRails.configure { |config| config.backend = :cli }

      assert_equal :cli, TypstRails.configuration.backend
    ensure
      TypstRails.configuration = nil
    end

    def test_backend_accepts_a_backend_instance
      backend = TypstRails::Backends::Cli.new
      TypstRails.configure { |config| config.backend = backend }

      assert_same backend, TypstRails.configuration.backend
    ensure
      TypstRails.configuration = nil
    end

    # validate! deliberately does not police the backend value; an unusable
    # one surfaces at resolve time with a clearer message.
    def test_validate_does_not_reject_an_unknown_backend_name
      config = TypstRails::Configuration.new
      config.backend = :nonexistent

      assert config.validate!
    end

    # A configured backend instance is used directly, bypassing auto-detection.
    # It must inherit from Backends::Base: Registry.resolve only short-circuits
    # on a Base, and treats anything else as a backend *name* to look up.
    def test_a_configured_backend_instance_is_used_by_the_renderer
      backend_class = Class.new(TypstRails::Backends::Base) do
        def available?
          true
        end

        def compile(_typ_path, _root_dir)
          "configured pdf"
        end
      end
      TypstRails.configure { |config| config.backend = backend_class.new }

      assert_equal "configured pdf", TypstRails::Renderer.new("= Test").render(nil, {})
    ensure
      TypstRails.configuration = nil
    end

    # The flip side: a duck-typed object that does not inherit from Base is
    # treated as a name, not an instance, and fails lookup.
    def test_a_backend_not_inheriting_from_base_is_treated_as_a_name
      duck = Object.new
      def duck.to_sym
        :not_registered
      end
      TypstRails.configure { |config| config.backend = duck }

      error = assert_raises(TypstRails::Error) { TypstRails::Renderer.new("= Test").render(nil, {}) }

      assert_includes error.message, "Unknown Typst backend"
    ensure
      TypstRails.configuration = nil
    end

    def test_a_configured_backend_name_is_resolved_through_the_registry
      TypstRails.configure { |config| config.backend = :cli }

      assert_kind_of TypstRails::Backends::Cli,
                     TypstRails::Backends::Registry.resolve(TypstRails.configuration.backend)
    ensure
      TypstRails.configuration = nil
    end

    # MARK: - validate! return value and messages

    def test_validate_returns_true_for_a_valid_configuration
      assert TypstRails::Configuration.new.validate!
    end

    def test_validate_error_message_names_the_empty_path
      config = TypstRails::Configuration.new
      config.typst_executable_path = ""

      error = assert_raises(ArgumentError) { config.validate! }

      assert_includes error.message, "cannot be nil or empty"
    end

    def test_validate_error_message_names_the_wrong_type
      config = TypstRails::Configuration.new
      config.typst_executable_path = 42

      error = assert_raises(ArgumentError) { config.validate! }

      assert_includes error.message, "must be a String"
    end

    def test_validate_rejects_a_pathname_default_root_path
      config = TypstRails::Configuration.new
      config.default_root_path = Object.new

      error = assert_raises(ArgumentError) { config.validate! }

      assert_includes error.message, "default_root_path must be a String or nil"
    end

    # MARK: - VERSION

    def test_version_is_a_frozen_string
      assert_kind_of String, TypstRails::VERSION
      assert_predicate TypstRails::VERSION, :frozen?
    end

    def test_version_looks_like_semver
      assert_match(/\A\d+\.\d+\.\d+/, TypstRails::VERSION)
    end

    def test_version_matches_the_gemspec
      spec = ::Gem::Specification.load(File.expand_path("../../typst-rails.gemspec", __dir__))

      assert_equal TypstRails::VERSION, spec.version.to_s
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
