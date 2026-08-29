# frozen_string_literal: true

require "cgi"
require "nokogiri"
require "reverse_markdown"

module TypstRails
  # Helper methods for working with Typst templates.
  #
  # This module provides utilities for:
  # - Escaping special Typst characters
  # - Converting HTML to Markdown and Typst
  # - Converting Markdown to Typst syntax
  # - Including external Markdown files
  # - URL encoding
  #
  # These helpers are included in the Renderer and available in Rails ERB templates
  # when using the Typst template handler.
  #
  # @example Using in Rails ERB template
  #   <%# app/views/reports/monthly.typ.erb %>
  #   <% data = { title: escape_typst(@title) } %>
  #   = #data.title
  #
  # @example Using standalone
  #   include TypstRails::Helpers
  #   safe_text = escape_typst("Price: $100")
  #   # => "Price: \\$100"
  module Helpers
    # MARK: - Text Escaping
    # Escapes text for safe use in Typst documents.
    #
    # Escapes special Typst characters that have syntactic meaning:
    # - `#` (code/scripting)
    # - `$` (math mode)
    # - `*` (emphasis)
    # - `_` (emphasis)
    # - `[`, `]` (content blocks)
    # - `\` (escape character)
    # - `<`, `>` (labels and references)
    # - `{`, `}` (code blocks)
    # - `@` (references)
    #
    # @param text [String, nil] The text to escape
    # @return [String] The escaped text, or empty string if text is nil
    # @raise [ArgumentError] if text is not a String or nil
    #
    # @example Escaping special characters
    #   escape_typst("Hello #world")
    #   # => "Hello \\#world"
    #
    # @example Escaping currency
    #   escape_typst("Price: $100")
    #   # => "Price: \\$100"
    #
    # @example Handling nil
    #   escape_typst(nil)
    #   # => ""
    #
    # @see https://typst.app/docs/reference/syntax/ Typst syntax reference
    def escape_typst(text)
      return "" if text.nil?
      raise ArgumentError, "text must be a String" unless text.is_a?(String)

      # Escape special Typst characters
      # See: https://typst.app/docs/reference/syntax/
      text.gsub(/([#\$*_\[\]\\<>{}@])/, '\\\\\1')
    end

    # MARK: - HTML Conversion

    # Converts HTML to Markdown for use in Typst documents.
    #
    # Typst has excellent support for Markdown syntax, making this a convenient
    # way to include HTML content in Typst documents. The conversion uses the
    # ReverseMarkdown library.
    #
    # @param html [String, nil] The HTML to convert
    # @param options [Hash] Options to pass to ReverseMarkdown
    # @return [String] The converted Markdown, or empty string if html is nil
    # @raise [ArgumentError] if html is not a String or nil
    # @raise [ArgumentError] if options is not a Hash
    # @raise [TypstRails::Error] if conversion fails
    #
    # @example Converting headings and text
    #   html_to_markdown("<h1>Title</h1><p>Content</p>")
    #   # => "# Title\n\nContent"
    #
    # @example Converting formatted text
    #   html_to_markdown("<strong>Bold</strong> text")
    #   # => "**Bold** text"
    #
    # @example With options
    #   html_to_markdown("<p>Text</p>", unknown_tags: :bypass)
    #
    # @see https://github.com/xijo/reverse_markdown ReverseMarkdown documentation
    def html_to_markdown(html, options = {})
      return "" if html.nil?
      raise ArgumentError, "html must be a String" unless html.is_a?(String)
      raise ArgumentError, "options must be a Hash" unless options.is_a?(Hash)

      begin
        ReverseMarkdown.convert(html, options)
      rescue StandardError => e
        raise Error, "Failed to convert HTML to Markdown: #{e.message}"
      end
    end

    # Converts HTML to Typst-compatible markup.
    #
    # This is a convenience method that combines html_to_markdown with
    # markdown_to_typst to convert HTML directly to Typst syntax.
    #
    # @param html [String, nil] The HTML to convert
    # @param options [Hash] Options to pass to the HTML converter
    # @return [String] Typst-compatible markup
    # @raise [ArgumentError] if html is not a String or nil
    # @raise [ArgumentError] if options is not a Hash
    # @raise [TypstRails::Error] if conversion fails
    #
    # @example Converting HTML headings to Typst
    #   html_to_typst("<h1>Title</h1>")
    #   # => "= Title\n\n"
    #
    # @example Converting formatted HTML
    #   html_to_typst("<strong>Bold</strong> and <em>italic</em>")
    #   # => "*Bold* and _italic_"
    #
    # @see #html_to_markdown
    # @see #markdown_to_typst
    def html_to_typst(html, options = {})
      markdown = html_to_markdown(html, options)
      markdown_to_typst(markdown)
    end

    # MARK: - Markdown Conversion

    # Converts Markdown to Typst syntax.
    #
    # Handles common Markdown patterns and converts them to Typst equivalents:
    # - Headings (`#` → `=`)
    # - Bold (`**text**` → `*text*`)
    # - Italic (`*text*` → `_text_`)
    # - Links (`[text](url)` → `#link("url")[text]`)
    # - Images (`![alt](url)` → `#image("url")`)
    #
    # @param markdown [String, nil] The Markdown text to convert
    # @return [String] Typst-compatible markup, or empty string if markdown is nil
    # @raise [ArgumentError] if markdown is not a String or nil
    #
    # @example Converting headings
    #   markdown_to_typst("# Title")
    #   # => "= Title"
    #
    # @example Converting subheadings
    #   markdown_to_typst("## Subtitle")
    #   # => "== Subtitle"
    #
    # @example Converting formatted text
    #   markdown_to_typst("**bold** and *italic*")
    #   # => "*bold* and _italic_"
    #
    # @example Converting links
    #   markdown_to_typst("[Typst](https://typst.app)")
    #   # => "#link(\"https://typst.app\")[Typst]"
    #
    # @see https://typst.app/docs/ Typst documentation
    def markdown_to_typst(markdown)
      return "" if markdown.nil?
      raise ArgumentError, "markdown must be a String" unless markdown.is_a?(String)

      result = markdown.dup

      # Convert Markdown headers to Typst headers
      # # Title -> = Title
      # ## Subtitle -> == Subtitle
      # etc.
      result.gsub!(/^(#{Regexp.quote("#")}{1,6})\s+(.+)$/) do
        "#{"=" * Regexp.last_match(1).length} #{Regexp.last_match(2)}"
      end

      # Convert Markdown bold to Typst bold, using placeholder bytes (\x01 text \x02)
      # so the italic pass below doesn't re-convert the resulting *text* markers.
      # **text** or __text__ -> *text*
      result.gsub!(/(\*\*|__)(.+?)\1/, "\x01\\2\x02")

      # Convert Markdown italic to Typst italic (underscore style)
      # *text* or _text_ -> _text_
      result.gsub!(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/, '_\1_')
      result.gsub!(/(?<!_)_(?!_)(.+?)(?<!_)_(?!_)/, '_\1_')

      # Replace bold placeholders with Typst bold markers
      result.gsub!("\x01", "*")
      result.gsub!("\x02", "*")

      # Convert Markdown code to Typst code
      # `code` -> `code` (same in Typst)

      # Convert Markdown images (must run before links, since ![alt](url)
      # would otherwise be matched by the link pattern below)
      # ![alt](url) -> #image("url")
      result.gsub!(/!\[([^\]]*)\]\(([^)]+)\)/, '#image("\2")')

      # Convert Markdown links
      # [text](url) -> #link("url")[text]
      result.gsub!(/\[([^\]]+)\]\(([^)]+)\)/, '#link("\2")[\1]')

      result
    end

    # Reads and includes Markdown content, converting it to Typst syntax.
    #
    # This method is useful for including external Markdown files in Typst
    # documents. The file is read and converted to Typst syntax.
    #
    # @param markdown_path [String] Path to the Markdown file (relative or absolute)
    # @return [String] Typst-compatible content from the file
    # @raise [ArgumentError] if markdown_path is not a String
    # @raise [ArgumentError] if markdown_path is empty
    # @raise [TypstRails::Error] if file not found
    # @raise [TypstRails::Error] if permission denied
    # @raise [TypstRails::Error] if file cannot be read
    #
    # @example Including a content file
    #   include_markdown("./content.md")
    #   # Returns the converted content of content.md
    #
    # @example Using in a Typst template
    #   # In your .typ.erb template:
    #   <%= include_markdown("sections/introduction.md") %>
    #
    # @note File path is relative to the current working directory
    def include_markdown(markdown_path)
      raise ArgumentError, "markdown_path must be a String" unless markdown_path.is_a?(String)
      raise ArgumentError, "markdown_path cannot be empty" if markdown_path.empty?

      begin
        markdown_content = File.read(markdown_path)
        markdown_to_typst(markdown_content)
      rescue Errno::ENOENT
        raise Error, "Markdown file not found: #{markdown_path}"
      rescue Errno::EACCES
        raise Error, "Permission denied reading Markdown file: #{markdown_path}"
      rescue StandardError => e
        raise Error, "Failed to read Markdown file #{markdown_path}: #{e.message}"
      end
    end

    # MARK: - URL Encoding

    # URL-encodes text for safe use in links.
    #
    # Uses CGI.escape to encode special characters for URL safety.
    # Useful when constructing URLs or query parameters in Typst templates.
    #
    # @param text [String, nil] The text to encode
    # @return [String] URL-encoded text, or empty string if text is nil
    # @raise [ArgumentError] if text is not a String or nil
    #
    # @example Encoding a search query
    #   url_encode("hello world")
    #   # => "hello+world"
    #
    # @example Encoding special characters
    #   url_encode("hello & goodbye")
    #   # => "hello+%26+goodbye"
    #
    # @example Building a URL
    #   query = url_encode(user_input)
    #   url = "https://example.com/search?q=#{query}"
    #
    # @see CGI.escape
    def url_encode(text)
      return "" if text.nil?
      raise ArgumentError, "text must be a String" unless text.is_a?(String)

      CGI.escape(text)
    end
  end
end
