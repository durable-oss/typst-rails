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
  end
end
