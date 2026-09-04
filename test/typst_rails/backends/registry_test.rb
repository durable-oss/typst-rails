# frozen_string_literal: true

require "test_helper"

module TypstRails
  module Backends
    class RegistryTest < Minitest::Test
      def test_registers_gem_and_cli_by_default
        assert_kind_of Gem, Registry.backends[:gem]
        assert_kind_of Cli, Registry.backends[:cli]
      end

      def test_resolve_returns_backend_instance_as_is
        backend = Cli.new

        assert_same backend, Registry.resolve(backend)
      end

      def test_resolve_with_explicit_name
        resolved = Registry.resolve(:cli)

        assert_kind_of Cli, resolved
      end

      def test_resolve_raises_for_unknown_name
        error = assert_raises(Error) { Registry.resolve(:nonexistent) }
        assert_includes error.message, "Unknown Typst backend"
      end

      def test_auto_detect_prefers_first_available_in_priority_order
        available_backend = stub(available?: true)
        unavailable_backend = stub(available?: false)

        with_registered_backends(unavailable: unavailable_backend, available: available_backend) do
          assert_same available_backend, Registry.resolve(:auto)
        end
      end

      def test_auto_detect_raises_when_nothing_available
        unavailable_backend = stub(available?: false)

        with_registered_backends(only: unavailable_backend) do
          error = assert_raises(Error) { Registry.resolve(:auto) }
          assert_includes error.message, "No Typst backend is available"
        end
      end

      def test_resolve_defaults_to_auto_when_nil
        available_backend = stub(available?: true)

        with_registered_backends(only: available_backend) do
          assert_same available_backend, Registry.resolve(nil)
        end
      end

      # MARK: - Registration semantics

      def test_register_adds_backend_and_appends_to_priority
        backend = stub(available?: true)

        with_clean_registry do
          Registry.register(:custom, backend)

          assert_same backend, Registry.backends[:custom]
          assert_equal [:custom], Registry.priority
        end
      end

      def test_register_accepts_a_string_name_and_stores_it_as_a_symbol
        backend = stub(available?: true)

        with_clean_registry do
          Registry.register("stringy", backend)

          assert_same backend, Registry.backends[:stringy]
          assert_includes Registry.priority, :stringy
          assert_same backend, Registry.resolve("stringy")
        end
      end

      def test_register_with_priority_false_is_resolvable_but_not_auto_detected
        opt_in = stub(available?: true)
        default = stub(available?: true)

        with_clean_registry do
          Registry.register(:opt_in, opt_in, priority: false)
          Registry.register(:default, default)

          refute_includes Registry.priority, :opt_in
          # Reachable when asked for by name...
          assert_same opt_in, Registry.resolve(:opt_in)
          # ...but never chosen by auto-detection.
          assert_same default, Registry.resolve(:auto)
        end
      end

      def test_re_registering_a_name_replaces_the_backend_without_duplicating_priority
        first = stub(available?: true)
        second = stub(available?: true)

        with_clean_registry do
          Registry.register(:dup, first)
          Registry.register(:dup, second)

          assert_same second, Registry.backends[:dup]
          assert_equal [:dup], Registry.priority, "re-registering must not duplicate the priority entry"
        end
      end

      def test_re_registering_with_priority_false_keeps_an_existing_priority_entry
        with_clean_registry do
          Registry.register(:kept, stub(available?: true))
          Registry.register(:kept, stub(available?: true), priority: false)

          assert_equal [:kept], Registry.priority
        end
      end

      def test_priority_order_follows_registration_order
        with_clean_registry do
          Registry.register(:first, stub(available?: false))
          Registry.register(:second, stub(available?: false))
          Registry.register(:third, stub(available?: false))

          assert_equal %i[first second third], Registry.priority
        end
      end

      def test_reset_clears_backends_and_priority
        with_clean_registry do
          Registry.register(:temp, stub(available?: true))
          Registry.reset!

          assert_empty Registry.backends
          assert_empty Registry.priority
        end
      end

      # MARK: - Resolution edge cases

      def test_auto_detect_skips_unavailable_backends_before_the_available_one
        skipped = mock("skipped")
        skipped.expects(:available?).returns(false)
        chosen = mock("chosen")
        chosen.expects(:available?).returns(true)
        never_asked = mock("never_asked")
        never_asked.expects(:available?).never

        with_registered_backends(skipped: skipped, chosen: chosen, never_asked: never_asked) do
          assert_same chosen, Registry.resolve(:auto)
        end
      end

      def test_auto_detect_tolerates_a_nil_backend_left_in_priority
        with_clean_registry do
          Registry.priority << :ghost
          Registry.register(:real, stub(available?: true))

          assert_kind_of Object, Registry.resolve(:auto)
        end
      end

      def test_resolve_with_an_explicit_instance_bypasses_availability_checks
        unavailable = mock("unavailable")
        unavailable.expects(:available?).never
        backend = Cli.new
        backend.stubs(:available?).returns(false)

        with_registered_backends(only: unavailable) do
          # An explicitly-passed instance wins even though it reports unavailable.
          assert_same backend, Registry.resolve(backend)
        end
      end

      def test_resolve_raises_for_an_unknown_name_even_when_others_are_available
        with_registered_backends(only: stub(available?: true)) do
          error = assert_raises(Error) { Registry.resolve(:nope) }

          assert_includes error.message, "Unknown Typst backend"
          assert_includes error.message, ":nope"
        end
      end

      def test_no_backend_available_error_names_both_remedies
        with_registered_backends(only: stub(available?: false)) do
          error = assert_raises(Error) { Registry.resolve(:auto) }

          assert_includes error.message, "`typst` gem"
          assert_includes error.message, "PATH"
        end
      end

      def test_default_registration_puts_the_gem_backend_ahead_of_the_cli
        gem_index = Registry.priority.index(:gem)
        cli_index = Registry.priority.index(:cli)

        refute_nil gem_index, "the :gem backend should be registered for auto-detection"
        refute_nil cli_index, "the :cli backend should be registered for auto-detection"
        assert_operator gem_index, :<, cli_index,
                        "the in-process gem backend should be preferred over shelling out to the CLI"
      end

      private

      # Runs the block against an empty registry, restoring the real
      # registration afterward.
      def with_clean_registry(&block)
        with_registered_backends(&block)
      end

      # Temporarily swaps out the registry's backends/priority for the duration
      # of the block, restoring the real (gem/cli) registration afterward.
      def with_registered_backends(only: nil, **named)
        original_backends = Registry.backends.dup
        original_priority = Registry.priority.dup

        Registry.reset!
        if only
          Registry.register(:only, only)
        else
          named.each { |name, backend| Registry.register(name, backend) }
        end

        yield
      ensure
        Registry.reset!
        original_backends.each { |name, backend| Registry.register(name, backend, priority: false) }
        original_priority.each { |name| Registry.priority << name }
      end
    end
  end
end
