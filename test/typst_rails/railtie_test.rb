# frozen_string_literal: true

require "English"
require "test_helper"

module TypstRails
  # Rails is deliberately not a development dependency of this gem, so the
  # Railtie is exercised in a subprocess that stands up a minimal
  # Rails::Railtie / ActionView pair. That keeps the real
  # `require "rails/railtie"` code path under test without dragging the whole
  # framework into the unit suite.
  class RailtieTest < Minitest::Test
    def test_registers_the_typ_template_handler_and_loads_rake_tasks
      run_subprocess_check("railtie_registration_check.rb")
    end

    # The Railtie is only required when Rails is actually detected, so a
    # non-Rails host must never end up with it loaded.
    def test_railtie_is_not_loaded_without_rails
      refute defined?(TypstRails::Railtie),
             "Railtie should not be loaded in a suite that runs without Rails"
    end

    # The rake task file the Railtie points at has to exist in the packaged
    # gem, or a Rails boot would blow up on `load`.
    def test_rake_task_file_referenced_by_the_railtie_exists
      tasks_path = File.expand_path("../../lib/tasks/typst_rails/tasks.rake", __dir__)

      assert_path_exists tasks_path
    end

    def test_rake_task_file_is_shipped_in_the_gem
      shipped = `git ls-files lib/tasks`.split("\n")

      assert_includes shipped, "lib/tasks/typst_rails/tasks.rake"
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
