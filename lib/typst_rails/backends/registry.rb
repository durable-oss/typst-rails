# frozen_string_literal: true

require "typst_rails/backends/base"

module TypstRails
  module Backends
    # Registry of available Typst compilation backends, and resolver that
    # picks the right one to use for a given configuration.
    #
    # Backends are tried in registration order; the first one whose
    # {Base#available?} returns true wins. This lets TypstRails prefer the
    # `typst` gem (fast, in-process) when it's installed, and fall back to
    # shelling out to the `typst` CLI otherwise.
    #
    # @example Registering a custom backend
    #   TypstRails::Backends::Registry.register(:my_backend, MyBackend.new)
    #   TypstRails.configure { |c| c.backend = :my_backend }
    module Registry
      class << self
        # @return [Hash{Symbol => Base}]
        def backends
          @backends ||= {}
        end

        # @return [Array<Symbol>] backend names in resolution priority order
        def priority
          @priority ||= []
        end

        # Registers a backend under the given name.
        #
        # @param name [Symbol] the backend's identifier (e.g. :gem, :cli)
        # @param backend [Base] the backend instance
        # @param priority [Boolean] whether to append this name to the auto-detection order
        # @return [void]
        def register(name, backend, priority: true)
          backends[name.to_sym] = backend
          self.priority << name.to_sym if priority && !self.priority.include?(name.to_sym)
        end

        # Resolves which backend to use.
        #
        # @param preference [Symbol, Base, nil] an explicit backend name, a backend
        #   instance, or nil/:auto to pick the first available backend in priority order
        # @return [Base] the resolved backend
        # @raise [TypstRails::Error] if no backend is available
        def resolve(preference = :auto)
          return preference if preference.is_a?(Base)
          return fetch_named_backend(preference) if preference && preference != :auto

          auto_detect
        end

        # Clears all registered backends. Primarily useful for tests.
        # @return [void]
        def reset!
          @backends = {}
          @priority = []
        end

        private

        def fetch_named_backend(name)
          backend = backends[name.to_sym]
          raise Error, "Unknown Typst backend: #{name.inspect}" unless backend

          backend
        end

        def auto_detect
          priority.each do |name|
            backend = backends[name]
            return backend if backend&.available?
          end

          raise Error, "No Typst backend is available. Install the `typst` gem, or " \
                       "install the Typst CLI and ensure it is on PATH."
        end
      end
    end
  end
end
