# frozen_string_literal: true

require "test_helper"

module TypstRails
  module Backends
    # Base is abstract: it exists to document the backend contract and to fail
    # loudly when a subclass forgets half of it. These tests pin that contract
    # so a subclass that only implements #available? cannot silently pass for
    # a working backend.
    class BaseTest < Minitest::Test
      # A deliberately incomplete backend: inherits without overriding anything.
      class IncompleteBackend < Base; end

      # Implements only half the contract.
      class HalfImplementedBackend < Base
        def available?
          true
        end
      end

      def test_available_raises_not_implemented
        error = assert_raises(NotImplementedError) { IncompleteBackend.new.available? }

        assert_includes error.message, "must implement #available?"
      end

      def test_compile_raises_not_implemented
        error = assert_raises(NotImplementedError) { IncompleteBackend.new.compile("/tmp/doc.typ", "/tmp") }

        assert_includes error.message, "must implement #compile"
      end

      def test_not_implemented_message_names_the_offending_subclass
        error = assert_raises(NotImplementedError) { IncompleteBackend.new.available? }

        assert_includes error.message, "IncompleteBackend"
      end

      def test_partial_implementation_still_raises_for_the_missing_half
        backend = HalfImplementedBackend.new

        assert_predicate backend, :available?
        assert_raises(NotImplementedError) { backend.compile("/tmp/doc.typ", "/tmp") }
      end

      # The built-in backends must actually satisfy the contract they inherit.
      def test_shipped_backends_override_the_abstract_methods
        [Cli, Gem].each do |klass|
          assert_operator klass, :<, Base, "#{klass} should inherit from Base"

          refute_equal Base.instance_method(:available?), klass.instance_method(:available?),
                       "#{klass} must override #available?"
          refute_equal Base.instance_method(:compile), klass.instance_method(:compile),
                       "#{klass} must override #compile"
        end
      end
    end
  end
end
