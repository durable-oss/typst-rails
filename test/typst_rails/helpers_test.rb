# frozen_string_literal: true

require "English"
require "test_helper"
require "typst_rails/helpers"

module TypstRails
  class HelpersTest < Minitest::Test
    include Helpers

    # Tests for escape_typst
    def test_escape_typst_with_hash
      assert_equal "\\#Hello", escape_typst("#Hello")
    end

    def test_escape_typst_with_dollar_sign
      assert_equal "Price: \\$100", escape_typst("Price: $100")
    end

    def test_escape_typst_with_asterisk
      assert_equal "\\*bold\\*", escape_typst("*bold*")
    end

    def test_escape_typst_with_underscore
      assert_equal "\\_italic\\_", escape_typst("_italic_")
    end

    def test_escape_typst_with_brackets
      assert_equal "\\[link\\]", escape_typst("[link]")
    end

    def test_escape_typst_with_backslash
      assert_equal "\\\\path\\\\to\\\\file", escape_typst("\\path\\to\\file")
    end

    def test_escape_typst_with_multiple_special_chars
      assert_equal "\\#\\$\\*\\_\\[\\]\\\\", escape_typst('#$*_[]\\')
    end

    def test_escape_typst_with_nil
      assert_equal "", escape_typst(nil)
    end

    def test_escape_typst_with_empty_string
      assert_equal "", escape_typst("")
    end

    def test_escape_typst_with_non_string_raises_error
      error = assert_raises(ArgumentError) do
        escape_typst(123)
      end
      assert_equal "text must be a String", error.message
    end

    # Tests for html_to_markdown
    def test_html_to_markdown_with_heading
      result = html_to_markdown("<h1>Title</h1>")

      assert_includes result, "Title"
    end

    def test_html_to_markdown_with_paragraph
      result = html_to_markdown("<p>Hello world</p>")

      assert_includes result, "Hello world"
    end

    def test_html_to_markdown_with_bold
      result = html_to_markdown("<strong>Bold text</strong>")

      assert_includes result, "**Bold text**"
    end

    def test_html_to_markdown_with_italic
      result = html_to_markdown("<em>Italic text</em>")

      assert_includes result, "_Italic text_"
    end

    def test_html_to_markdown_with_link
      result = html_to_markdown('<a href="https://example.com">Link</a>')

      assert_includes result, "[Link](https://example.com)"
    end

    def test_html_to_markdown_with_list
      html = "<ul><li>Item 1</li><li>Item 2</li></ul>"
      result = html_to_markdown(html)

      assert_includes result, "Item 1"
      assert_includes result, "Item 2"
    end

    def test_html_to_markdown_with_nil
      assert_equal "", html_to_markdown(nil)
    end

    def test_html_to_markdown_with_empty_string
      assert_equal "", html_to_markdown("")
    end

    def test_html_to_markdown_with_non_string_raises_error
      error = assert_raises(ArgumentError) do
        html_to_markdown(123)
      end
      assert_equal "html must be a String", error.message
    end

    def test_html_to_markdown_with_non_hash_options_raises_error
      error = assert_raises(ArgumentError) do
        html_to_markdown("<p>Test</p>", "not a hash")
      end
      assert_equal "options must be a Hash", error.message
    end

    def test_html_to_markdown_wraps_conversion_failure
      ReverseMarkdown.stubs(:convert).raises(StandardError.new("parser exploded"))

      error = assert_raises(Error) do
        html_to_markdown("<p>Test</p>")
      end
      assert_includes error.message, "Failed to convert HTML to Markdown"
      assert_includes error.message, "parser exploded"
    end

    # Tests for markdown_to_typst
    def test_markdown_to_typst_converts_h1
      assert_equal "= Title", markdown_to_typst("# Title")
    end

    def test_markdown_to_typst_converts_h2
      assert_equal "== Subtitle", markdown_to_typst("## Subtitle")
    end

    def test_markdown_to_typst_converts_h3
      assert_equal "=== Level 3", markdown_to_typst("### Level 3")
    end

    def test_markdown_to_typst_converts_bold_double_asterisk
      assert_equal "*bold*", markdown_to_typst("**bold**")
    end

    def test_markdown_to_typst_converts_bold_double_underscore
      assert_equal "*bold*", markdown_to_typst("__bold__")
    end

    def test_markdown_to_typst_converts_italic_asterisk
      assert_equal "_italic_", markdown_to_typst("*italic*")
    end

    def test_markdown_to_typst_converts_italic_underscore
      assert_equal "_italic_", markdown_to_typst("_italic_")
    end

    def test_markdown_to_typst_converts_links
      result = markdown_to_typst("[text](https://example.com)")

      assert_equal '#link("https://example.com")[text]', result
    end

    def test_markdown_to_typst_converts_images
      result = markdown_to_typst("![alt text](image.png)")

      assert_equal '#image("image.png")', result
    end

    def test_markdown_to_typst_with_nil
      assert_equal "", markdown_to_typst(nil)
    end

    def test_markdown_to_typst_with_empty_string
      assert_equal "", markdown_to_typst("")
    end

    def test_markdown_to_typst_with_non_string_raises_error
      error = assert_raises(ArgumentError) do
        markdown_to_typst(123)
      end
      assert_equal "markdown must be a String", error.message
    end

    def test_markdown_to_typst_preserves_code_blocks
      result = markdown_to_typst("`code`")

      assert_equal "`code`", result
    end

    # Tests for html_to_typst
    def test_html_to_typst_converts_heading
      result = html_to_typst("<h1>Title</h1>")

      assert_includes result, "= Title"
    end

    def test_html_to_typst_converts_bold
      result = html_to_typst("<strong>Bold</strong>")

      assert_includes result, "*Bold*"
    end

    def test_html_to_typst_converts_link
      result = html_to_typst('<a href="https://example.com">Link</a>')

      assert_includes result, '#link("https://example.com")[Link]'
    end

    # Tests for include_markdown
    def test_include_markdown_reads_and_converts_file
      markdown_content = "# Title\n\nSome **bold** text."
      file = Tempfile.new(["test_", ".md"])
      file.write(markdown_content)
      file.close

      begin
        result = include_markdown(file.path)

        assert_includes result, "= Title"
        assert_includes result, "*bold*"
      ensure
        file.unlink
      end
    end

    def test_include_markdown_with_non_string_raises_error
      error = assert_raises(ArgumentError) do
        include_markdown(123)
      end
      assert_equal "markdown_path must be a String", error.message
    end

    def test_include_markdown_with_empty_string_raises_error
      error = assert_raises(ArgumentError) do
        include_markdown("")
      end
      assert_equal "markdown_path cannot be empty", error.message
    end

    def test_include_markdown_with_nonexistent_file_raises_error
      error = assert_raises(Error) do
        include_markdown("/nonexistent/file.md")
      end
      assert_includes error.message, "Markdown file not found"
    end

    def test_include_markdown_wraps_unexpected_read_failure
      File.stubs(:read).raises(StandardError.new("disk exploded"))

      error = assert_raises(Error) do
        include_markdown("some_file.md")
      end
      assert_includes error.message, "Failed to read Markdown file some_file.md"
      assert_includes error.message, "disk exploded"
    end

    def test_include_markdown_with_permission_denied
      skip "Skipping permission test on this platform" if RUBY_PLATFORM =~ /mswin|mingw|windows/

      file = Tempfile.new(["test_", ".md"])
      file.write("# Test")
      file.close
      File.chmod(0o000, file.path)

      begin
        error = assert_raises(Error) do
          include_markdown(file.path)
        end
        assert_includes error.message, "Permission denied"
      ensure
        File.chmod(0o644, file.path)
        file.unlink
      end
    end

    # Tests for url_encode
    def test_url_encode_encodes_spaces
      assert_equal "hello+world", url_encode("hello world")
    end

    def test_url_encode_encodes_special_chars
      assert_equal "hello%26world", url_encode("hello&world")
    end

    def test_url_encode_with_nil
      assert_equal "", url_encode(nil)
    end

    def test_url_encode_with_empty_string
      assert_equal "", url_encode("")
    end

    def test_url_encode_with_non_string_raises_error
      error = assert_raises(ArgumentError) do
        url_encode(123)
      end
      assert_equal "text must be a String", error.message
    end

    def test_url_encode_handles_unicode
      result = url_encode("こんにちは")

      refute_equal "こんにちは", result
      assert_includes result, "%"
    end
    # MARK: - markdown_to_typst edge cases
    #
    # The conversion is a chain of regex passes over the whole string, which
    # makes ordering and nesting the interesting cases. These pin current
    # behaviour so a future rewrite of the pass order is caught.

    def test_markdown_to_typst_converts_all_six_heading_levels
      (1..6).each do |level|
        markdown = "#{"#" * level} Heading"
        expected = "#{"=" * level} Heading"

        assert_equal expected, markdown_to_typst(markdown), "level #{level} heading"
      end
    end

    # Typst has no seventh heading level, and Markdown stops at six, so seven
    # hashes must be left alone rather than becoming seven equals signs.
    def test_markdown_to_typst_leaves_seven_hashes_alone
      assert_equal "####### seven", markdown_to_typst("####### seven")
    end

    # A heading marker requires whitespace after the hashes; without it the
    # text is a Typst code expression and must survive untouched.
    def test_markdown_to_typst_requires_whitespace_after_heading_hashes
      assert_equal "#no-space", markdown_to_typst("#no-space")
    end

    def test_markdown_to_typst_only_converts_headings_at_line_start
      assert_equal "text # not a heading", markdown_to_typst("text # not a heading")
    end

    def test_markdown_to_typst_converts_headings_on_every_line
      result = markdown_to_typst("# One\n## Two\n### Three")

      assert_equal "= One\n== Two\n=== Three", result
    end

    # Bold is converted through placeholder bytes so the italic pass cannot
    # re-enter the markers it just wrote. Nested emphasis is the case that
    # ordering bug would break.
    def test_markdown_to_typst_handles_italic_nested_inside_bold
      assert_equal "*bold with _nested_ inside*", markdown_to_typst("**bold with *nested* inside**")
    end

    def test_markdown_to_typst_converts_multiple_bold_runs_on_one_line
      assert_equal "*a* *b*", markdown_to_typst("**a** **b**")
    end

    def test_markdown_to_typst_converts_mixed_underscore_bold_and_italic
      assert_equal "*bold* and _italic_", markdown_to_typst("__bold__ and _italic_")
    end

    # Underscores inside a word are not emphasis in Markdown, and identifiers
    # like snake_case must not be mangled.
    def test_markdown_to_typst_leaves_intra_word_underscores_alone
      assert_equal "snake_case_word here", markdown_to_typst("snake_case_word here")
    end

    # Images must be converted before links, otherwise the link pattern would
    # claim the "[alt](url)" tail of an image and drop the "!".
    def test_markdown_to_typst_converts_images_before_links
      assert_equal '#image("img_1.png")', markdown_to_typst("![alt](img_1.png)")
    end

    def test_markdown_to_typst_converts_an_image_wrapped_in_a_link
      result = markdown_to_typst("[![alt](img.png)](https://ex.com)")

      assert_equal '#link("https://ex.com")[#image("img.png")]', result
    end

    def test_markdown_to_typst_converts_multiple_links_on_one_line
      result = markdown_to_typst("[text](url) and [more](url2)")

      assert_equal '#link("url")[text] and #link("url2")[more]', result
    end

    # A URL containing underscores must survive the italic pass intact.
    def test_markdown_to_typst_preserves_underscores_inside_link_urls
      result = markdown_to_typst("[link](https://ex.com/a_b_c)")

      assert_equal '#link("https://ex.com/a_b_c")[link]', result
    end

    def test_markdown_to_typst_leaves_list_markers_alone
      assert_equal "- item", markdown_to_typst("- item")
    end

    def test_markdown_to_typst_does_not_mutate_the_argument
      markdown = +"# Title with **bold**"
      original = markdown.dup

      markdown_to_typst(markdown)

      assert_equal original, markdown, "markdown_to_typst must not modify the string it was given"
    end

    def test_markdown_to_typst_is_idempotent_for_already_converted_headings
      assert_equal "= Title", markdown_to_typst(markdown_to_typst("# Title"))
    end

    def test_markdown_to_typst_handles_multiline_documents
      markdown = "# Title\n\nSome **bold** text.\n\n## Section\n\nA [link](https://ex.com).\n"
      expected = "= Title\n\nSome *bold* text.\n\n== Section\n\nA #link(\"https://ex.com\")[link].\n"

      assert_equal expected, markdown_to_typst(markdown)
    end

    # MARK: - markdown_to_typst combined emphasis
    #
    # ***text*** is a single Markdown token meaning bold+italic. It has to be
    # matched before the plain bold pass, which would otherwise consume two of
    # the three markers and strand the leftover one inside the text.

    def test_markdown_to_typst_converts_triple_asterisk_to_bold_italic
      assert_equal "*_both_*", markdown_to_typst("***both***")
    end

    def test_markdown_to_typst_converts_triple_underscore_to_bold_italic
      assert_equal "*_both_*", markdown_to_typst("___both___")
    end

    def test_markdown_to_typst_converts_combined_emphasis_inside_a_sentence
      assert_equal "a *_b_* c", markdown_to_typst("a ***b*** c")
    end

    def test_markdown_to_typst_converts_multiple_combined_emphasis_runs
      assert_equal "*_a_* and *_b_*", markdown_to_typst("***a*** and ***b***")
    end

    def test_markdown_to_typst_emits_balanced_markers_for_combined_emphasis
      result = markdown_to_typst("***both***")

      assert_equal 2, result.count("*"), "bold markers should be balanced"
      assert_equal 2, result.count("_"), "italic markers should be balanced"
    end

    # MARK: - markdown_to_typst placeholder safety
    #
    # The emphasis passes stage their markers as private-use sentinels. Any of
    # those characters already in the caller's text must survive untouched.

    def test_markdown_to_typst_preserves_private_use_sentinel_characters
      ["\u{E000}", "\u{E001}", "\u{E002}", "\u{E003}", "\u{E004}"].each do |char|
        input = "a #{char} b"

        assert_equal input, markdown_to_typst(input), "#{char.ord.to_s(16)} should round-trip"
      end
    end

    def test_markdown_to_typst_preserves_several_sentinels_in_order
      input = "\u{E000}X\u{E002}Y\u{E004}"

      assert_equal input, markdown_to_typst(input)
    end

    def test_markdown_to_typst_preserves_sentinels_alongside_real_emphasis
      assert_equal "\u{E000} *b*", markdown_to_typst("\u{E000} **b**")
    end

    # The control bytes the old implementation used as placeholders are
    # ordinary text now and must pass through unchanged.
    def test_markdown_to_typst_preserves_legacy_control_bytes
      assert_equal "a \x01 b", markdown_to_typst("a \x01 b")
      assert_equal "a \x02 b", markdown_to_typst("a \x02 b")
    end

    # Protection state must not leak between calls.
    def test_markdown_to_typst_placeholder_state_does_not_leak_between_calls
      markdown_to_typst("\u{E000}\u{E001}\u{E002}")

      assert_equal "plain", markdown_to_typst("plain")
    end

    # MARK: - escape_typst coverage for the remaining special characters

    def test_escape_typst_escapes_angle_brackets
      assert_equal "\\<label\\>", escape_typst("<label>")
    end

    def test_escape_typst_escapes_braces
      assert_equal "\\{code\\}", escape_typst("{code}")
    end

    def test_escape_typst_escapes_at_sign
      assert_equal "\\@reference", escape_typst("@reference")
    end

    def test_escape_typst_escapes_every_documented_character
      '#$*_[]\\<>{}@'.each_char do |char|
        assert_equal "\\#{char}", escape_typst(char), "#{char.inspect} should be escaped"
      end
    end

    def test_escape_typst_leaves_ordinary_text_untouched
      assert_equal "Hello, world 123.", escape_typst("Hello, world 123.")
    end

    def test_escape_typst_preserves_newlines
      assert_equal "line one\nline two", escape_typst("line one\nline two")
    end

    def test_escape_typst_handles_unicode
      assert_equal "café — naïve 日本語", escape_typst("café — naïve 日本語")
    end

    def test_escape_typst_output_is_not_double_escaped_by_a_second_pass
      once = escape_typst("$100")
      twice = escape_typst(once)

      assert_equal "\\$100", once
      assert_equal "\\\\\\$100", twice,
                   "escape_typst is not idempotent; callers must escape exactly once"
    end

    # MARK: - html_to_typst

    def test_html_to_typst_with_nil_returns_empty_string
      assert_empty html_to_typst(nil)
    end

    def test_html_to_typst_converts_nested_structure
      result = html_to_typst("<h2>Section</h2><p>Some <strong>bold</strong> text.</p>")

      assert_includes result, "== Section"
      assert_includes result, "*bold*"
    end

    def test_html_to_typst_propagates_argument_errors_from_the_html_stage
      assert_raises(ArgumentError) { html_to_typst(123) }
    end

    def test_html_to_typst_passes_options_through_to_the_html_converter
      ReverseMarkdown.expects(:convert).with("<p>x</p>", { unknown_tags: :bypass }).returns("x")

      assert_equal "x", html_to_typst("<p>x</p>", unknown_tags: :bypass)
    end

    # MARK: - include_markdown

    def test_include_markdown_converts_headings_and_emphasis_from_the_file
      file = Tempfile.new(["fixture", ".md"])
      file.write("# Title\n\nSome **bold** text.\n")
      file.close

      result = include_markdown(file.path)

      assert_includes result, "= Title"
      assert_includes result, "*bold*"
    ensure
      file&.unlink
    end

    def test_include_markdown_handles_an_empty_file
      file = Tempfile.new(["empty", ".md"])
      file.close

      assert_empty include_markdown(file.path)
    ensure
      file&.unlink
    end

    def test_include_markdown_error_message_names_the_missing_path
      error = assert_raises(Error) { include_markdown("/no/such/file.md") }

      assert_includes error.message, "/no/such/file.md"
    end

    # MARK: - url_encode

    def test_url_encode_encodes_reserved_url_characters
      assert_equal "a%2Fb%3Fc%3Dd%26e", url_encode("a/b?c=d&e")
    end

    def test_url_encode_leaves_unreserved_characters_alone
      assert_equal "abcXYZ123-_.", url_encode("abcXYZ123-_.")
    end

    def test_url_encode_round_trips_through_cgi_unescape
      original = "hello world & friends/日本語"

      assert_equal original, CGI.unescape(url_encode(original))
    end
    # MARK: - Module surface
    #
    # These helpers are called from user ERB templates, so their visibility is
    # part of the public API. The module also defines private placeholder
    # helpers; a stray `private` above the wrong method would break every
    # template silently.

    def test_documented_helpers_are_public_when_included
      host = Class.new { include TypstRails::Helpers }.new

      %i[escape_typst html_to_markdown html_to_typst markdown_to_typst include_markdown url_encode].each do |name|
        assert_respond_to host, name, "#{name} must stay part of the public helper API"
      end
    end

    def test_placeholder_helpers_are_private
      host_class = Class.new { include TypstRails::Helpers }

      %i[protect_placeholder_bytes restore_placeholder_bytes].each do |name|
        refute_respond_to host_class.new, name, "#{name} is an implementation detail"
        assert host_class.private_method_defined?(name), "#{name} should still exist as a private method"
      end
    end

    # The Renderer includes Helpers so templates can call them through it.
    def test_renderer_exposes_the_helpers
      renderer = TypstRails::Renderer.new("= Test")

      assert_respond_to renderer, :escape_typst
      assert_respond_to renderer, :markdown_to_typst
    end
  end
end
