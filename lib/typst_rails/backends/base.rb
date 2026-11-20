# frozen_string_literal: true

require "typst_rails/errors"

module TypstRails
  module Backends
    # Abstract interface for a Typst compilation backend.
    #
    # A backend is responsible for turning a Typst source file (plus a root
    # directory for relative imports) into PDF bytes. Subclasses implement
    # {#available?} and {#compile}.
    #
    # @abstract
    class Base
      # @return [Boolean] whether this backend can be used in the current environment
      #   (e.g. the `typst` executable is on PATH, or the `typst` gem is loaded)
      def available?
        raise NotImplementedError, "#{self.class} must implement #available?"
      end

      # Compiles a Typst source file to PDF.
      #
      # @param typ_path [String] path to the .typ source file to compile
      # @param root_dir [String] root directory for resolving relative imports
      # @yieldparam diagnostics [String] Typst's diagnostic output from a
      #   successful compile, such as warnings. Backends that can see it
      #   should yield it when a block is given; the Renderer parses it and
      #   passes the warnings to {TypstRails::Configuration#on_warning}.
      #   Yielding is optional.
      # @return [String] binary PDF data
      # @raise [TypstRails::CompileError] if Typst rejects the source; pass
      #   Typst's diagnostic output as the message so it can be parsed
      # @raise [TypstRails::Error] if compilation fails for another reason
      def compile(typ_path, root_dir)
        raise NotImplementedError, "#{self.class} must implement #compile"
      end

      private

      # Options from {TypstRails::Configuration#compile_options}, or an empty
      # Hash when nothing is configured. TypstRails.configuration is checked
      # with respond_to? first because the top-level module is not loaded when
      # "typst_rails/renderer" is required on its own.
      #
      # @return [Hash{Symbol => Object}]
      def configured_compile_options
        return {} unless TypstRails.respond_to?(:configuration)

        TypstRails.configuration&.compile_options || {}
      end
    end
  end
end
