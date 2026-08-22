# frozen_string_literal: true

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
      # @return [String] binary PDF data
      # @raise [TypstRails::Error] if compilation fails
      def compile(typ_path, root_dir)
        raise NotImplementedError, "#{self.class} must implement #compile"
      end
    end
  end
end
