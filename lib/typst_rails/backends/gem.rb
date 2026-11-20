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

      # Passes {TypstRails::Configuration#compile_options} to `Typst::Pdf.new`
      # as its `font_paths:` and `ignore_system_fonts:` options.
      #
      # @see Base#compile
      def compile(typ_path, root_dir)
        ::Typst::Pdf.new(file: typ_path, root: root_dir, **gem_options).compiled.document
      rescue StandardError => e
        raise Error, "Typst compilation failed: #{e.message}"
      end

      private

      # Options for Typst::Pdf.new, under the keys the `typst` gem expects.
      # PDF standards are left out when none are configured, so a plain
      # compile does not pass an empty list.
      def gem_options
        options = configured_compile_options.slice(:font_paths, :ignore_system_fonts, :pdf_standards)
        options.delete(:pdf_standards) if Array(options[:pdf_standards]).empty?
        options
      end
    end
  end
end
