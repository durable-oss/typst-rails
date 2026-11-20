# frozen_string_literal: true

require "typst_rails/backends/base"

module TypstRails
  module Backends
    # Compiles Typst documents in-process using the `typst` RubyGem
    # (https://rubygems.org/gems/typst), a native extension that embeds the
    # Typst compiler.
    #
    # This avoids the cost of spawning a subprocess for every render and does
    # not require a separately installed `typst` executable. It is used
    # automatically when the `typst` gem is available; add it to your Gemfile
    # to opt in:
    #
    #   gem "typst"
    #
    # @example
    #   backend = TypstRails::Backends::Gem.new
    #   backend.available? #=> true, if the `typst` gem is loaded
    #   pdf_data = backend.compile("/tmp/doc.typ", "/tmp")
    class Gem < Base
      # @return [Boolean] whether the `typst` gem is installed and loadable
      def available?
        return true if defined?(::Typst::Pdf)

        begin
          require "typst"
          true
        rescue LoadError
          false
        end
      end

      # @see Base#compile
      def compile(typ_path, root_dir)
        ::Typst::Pdf.new(file: typ_path, root: root_dir, **gem_options).compiled.document
      rescue StandardError => e
        raise Error, "Typst compilation failed: #{e.message}"
      end

      private

      # TypstRails.configuration raises NoMethodError when only
      # "typst_rails/renderer" has been required, so check for it first.
      def configured_compile_options
        return {} unless TypstRails.respond_to?(:configuration)

        TypstRails.configuration&.compile_options || {}
      end

      # Options for Typst::Pdf.new. Empty values are left out so that a plain
      # compile passes only file and root, as before.
      def gem_options
        options = {}
        standards = configured_compile_options.fetch(:pdf_standards, [])
        options[:pdf_standards] = standards unless standards.empty?
        options
      end
    end
  end
end
