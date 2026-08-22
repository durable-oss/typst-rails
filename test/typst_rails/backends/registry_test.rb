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

      private

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
