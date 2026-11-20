# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

module TypstRails
  # Compiles real documents with each built-in backend to check that
  # font_paths and ignore_system_fonts reach Typst.
  #
  # Which font a document used is read from the PDF's font dictionaries,
  # which name each embedded font as "/BaseFont/ABCDEF+PostScriptName".
  #
  # The custom-font cases need a font file that is not embedded in Typst.
  # Rather than vendor one, they look for a common system font with
  # fc-match, copy it into a temporary directory, and skip when none is
  # found.
  class FontCompilationTest < Minitest::Test
    # Family name and PostScript name prefix of fonts the custom-font cases
    # can use. Neither ships inside Typst.
    CANDIDATE_FONTS = [
      ["Liberation Sans", "LiberationSans"],
      ["DejaVu Sans", "DejaVuSans"]
    ].freeze

    def setup
      @original_configuration = TypstRails.configuration
    end

    def teardown
      TypstRails.configuration = @original_configuration
    end

    %i[cli gem].each do |backend_name|
      # Typst embeds Libertinus Serif, so this needs no font from the system.
      define_method(:"test_#{backend_name}_compiles_with_embedded_fonts_when_ignoring_system_fonts") do
        backend = backend_or_skip(backend_name)
        TypstRails.configure { |c| c.ignore_system_fonts = true }

        pdf = compile_with(backend, "Libertinus Serif")

        assert_includes base_fonts(pdf), "LibertinusSerif"
      end

      define_method(:"test_#{backend_name}_uses_a_font_from_a_configured_font_path") do
        backend = backend_or_skip(backend_name)
        family, postscript_name, font_file = system_font_or_skip

        Dir.mktmpdir("typst-rails-fonts") do |font_dir|
          FileUtils.cp(font_file, font_dir)
          # Ignoring system fonts means the font can only come from font_dir.
          TypstRails.configure do |c|
            c.font_paths = font_dir
            c.ignore_system_fonts = true
          end

          pdf = compile_with(backend, family)

          assert_includes base_fonts(pdf), postscript_name
        end
      end

      # The control for the case above: the same font is installed on the
      # system, but ignore_system_fonts keeps Typst from finding it.
      define_method(:"test_#{backend_name}_ignore_system_fonts_hides_system_fonts") do
        backend = backend_or_skip(backend_name)
        family, postscript_name, = system_font_or_skip
        TypstRails.configure { |c| c.ignore_system_fonts = true }

        pdf = compile_with(backend, family)

        refute_includes base_fonts(pdf), postscript_name
      end
    end

    private

    def backend_or_skip(name)
      backend = Backends::Registry.resolve(name)
      skip "the #{name} backend is not available" unless backend.available?
      backend
    end

    # Returns [family, PostScript name prefix, file] for the first candidate
    # font fc-match resolves to itself rather than to a substitute.
    def system_font_or_skip
      CANDIDATE_FONTS.each do |family, postscript_name|
        # rubocop:disable Style/FormatStringToken -- fontconfig's format, not Ruby's
        output, status = Open3.capture2("fc-match", "--format=%{family}\n%{file}", family)
        # rubocop:enable Style/FormatStringToken
        next unless status.success?

        families, file = output.split("\n", 2)
        next unless families.to_s.split(",").include?(family) && file && File.file?(file)

        return [family, postscript_name, file]
      end

      skip "none of #{CANDIDATE_FONTS.map(&:first).join(", ")} was found with fc-match"
    rescue Errno::ENOENT
      skip "fc-match is not installed, so no font file could be located"
    end

    # fallback: false stops Typst substituting another font, so a missing
    # family leaves its text out rather than rendering it in something else.
    def compile_with(backend, family)
      Dir.mktmpdir do |dir|
        typ_path = File.join(dir, "doc.typ")
        File.write(typ_path, "#set text(font: #{family.inspect}, fallback: false)\nHello fonts")
        backend.compile(typ_path, dir)
      end
    end

    def base_fonts(pdf)
      pdf.b.scan(%r{/BaseFont\s*/[A-Z]{6}\+([A-Za-z0-9-]+)}).flatten.join(" ")
    end
  end
end
