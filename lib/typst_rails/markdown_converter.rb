# frozen_string_literal: true

module TypstRails
  # Converts one Markdown document to Typst markup. Backs
  # {Helpers#markdown_to_typst}; each conversion uses a new instance, so the
  # state it keeps between passes never outlives the call.
  #
  # Markup the conversion writes (headings, list markers, links, images,
  # code) is stashed behind placeholders as it is made. The text left over is
  # escaped with {Helpers#escape_typst}, so it reads as written, and the
  # stashed markup is then put back.
  #
  # @api private
  class MarkdownConverter
    include Helpers

    # MARK: - Placeholders
    #
    # The conversion rewrites emphasis in several regex passes. Each pass
    # must not re-match markers written by an earlier one, so markers are
    # staged as these private sentinel bytes and swapped for real Typst syntax
    # at the very end.
    #
    # They are drawn from the Unicode private use area rather than plain
    # control bytes so they cannot collide with anything a text pipeline is
    # likely to emit. Any that do appear in the source are held aside by
    # {#protect_placeholder_bytes} and put back verbatim afterwards.
    BOLD_OPEN = "\u{E000}"
    BOLD_CLOSE = "\u{E001}"
    ITALIC_OPEN = "\u{E002}"
    ITALIC_CLOSE = "\u{E003}"

    # Sentinel standing in for a placeholder byte that was already present in
    # the caller's input.
    LITERAL_PLACEHOLDER = "\u{E004}"

    # Delimit the index of a stashed token: Typst markup the conversion has
    # already written, such as a heading marker, a link or a code span,
    # held aside so the escaping pass leaves it intact.
    STASH_OPEN = "\u{E005}"
    STASH_CLOSE = "\u{E006}"

    # Follows a stashed embedded expression (#link, #image). Typst would read
    # a "(" or a "." and a name straight after one as part of the expression,
    # so there it becomes a ";" to end the expression, and elsewhere it is
    # dropped.
    EXPRESSION_END = "\u{E007}"

    # All sentinels this class reserves, in a single character class.
    PLACEHOLDER_PATTERN = /[\u{E000}-\u{E007}]/.freeze

    STASH_PATTERN = /\u{E005}(\d+)\u{E006}/.freeze

    # Fenced code blocks (``` or ~~~) and single-line inline code spans.
    # Fences come first so their backticks are not read as inline spans.
    CODE_PATTERN = /^(`{3,}|~{3,})[^\n]*\n.*?^\1[ \t]*$|(`+)[^`\n][^\n]*?\2(?!`)/m.freeze

    # A Markdown backslash escape: a backslash before ASCII punctuation, or at
    # the end of a line, where it is a hard line break.
    BACKSLASH_ESCAPE_PATTERN = %r{\\([!-/:-@\[-`\{-~])|\\(?=\r?\n)}.freeze

    HEADING_PATTERN = /^(\#{1,6})[ \t]+(.+)$/.freeze

    # Bullets (-, +, *) and ordered items (1. or 1)) followed by whitespace.
    LIST_MARKER_PATTERN = /^([ \t]*)([-+*]|\d+[.)])(?=[ \t])/.freeze

    # A link destination with an optional quoted title, which Typst has no
    # place for and is dropped.
    LINK_TARGET = /\(\s*(\S+?)(?:\s+"[^"]*")?\s*\)/.freeze
    IMAGE_PATTERN = /!\[[^\]]*\]#{LINK_TARGET}/.freeze
    LINK_PATTERN = /\[([^\]]+)\]#{LINK_TARGET}/.freeze
    AUTOLINK_PATTERN = /<((?:https?|mailto):[^\s<>]+)>/.freeze

    # One piece of stashed markup, and the source text it came from, which is
    # what a link destination needs when the piece turns up inside one.
    StashedToken = Struct.new(:markup, :literal)

    private_constant :BOLD_OPEN, :BOLD_CLOSE, :ITALIC_OPEN, :ITALIC_CLOSE, :LITERAL_PLACEHOLDER,
                     :STASH_OPEN, :STASH_CLOSE, :EXPRESSION_END, :PLACEHOLDER_PATTERN, :STASH_PATTERN,
                     :CODE_PATTERN, :BACKSLASH_ESCAPE_PATTERN, :HEADING_PATTERN, :LIST_MARKER_PATTERN,
                     :LINK_TARGET, :IMAGE_PATTERN, :LINK_PATTERN, :AUTOLINK_PATTERN, :StashedToken

    # @param markdown [String] the Markdown source
    def initialize(markdown)
      super()
      @markdown = markdown
      @tokens = []
    end

    # @return [String] Typst-compatible markup
    def convert
      # The passes below use placeholder bytes to mark text they have already
      # handled. Any such bytes already in the source would be
      # indistinguishable from our own, so they are held aside and restored at
      # the end.
      result = protect_placeholder_bytes(@markdown.dup)

      result = stash_literal_markdown(result)
      result = stash_line_markers(result)
      result = stash_links(result)
      result = convert_inline_markdown(result)

      restore_placeholder_bytes(restore_stash(result))
    end

    private

    # MARK: - Markdown conversion passes

    # Holds aside the parts of the source whose contents are literal: code,
    # which is the same in Typst as in Markdown, and backslash escapes, which
    # stand for their character.
    def stash_literal_markdown(text)
      text = text.gsub(CODE_PATTERN) { |code| stash(code, code) }

      text.gsub(BACKSLASH_ESCAPE_PATTERN) do
        char = Regexp.last_match(1)
        next stash("\\", "") unless char

        stash("\\#{char}", char)
      end
    end

    # Converts the markers that only mean something at the start of a line:
    # headings, and list items. Markdown bullets all become Typst's "-", since
    # "+" would make a numbered item.
    def stash_line_markers(text)
      text = text.gsub(HEADING_PATTERN) do
        heading = "#{"=" * Regexp.last_match(1).length} "
        "#{stash(heading, heading)}#{Regexp.last_match(2)}"
      end

      text.gsub(LIST_MARKER_PATTERN) do
        indent = Regexp.last_match(1)
        marker = Regexp.last_match(2)
        bullet = marker.match?(/\A\d/) ? "#{marker.to_i}." : "-"
        "#{indent}#{stash(bullet, marker)}"
      end
    end

    # Converts images and links, writing their destinations as Typst string
    # literals. Images go first, since ![alt](url) also matches the link
    # pattern, and so an image can sit inside a link's text.
    def stash_links(text)
      text = text.gsub(AUTOLINK_PATTERN) do
        stash_expression("#link(#{typst_string(Regexp.last_match(1))})")
      end

      text = text.gsub(IMAGE_PATTERN) do
        stash_expression("#image(#{typst_string(Regexp.last_match(1))})")
      end

      text.gsub(LINK_PATTERN) do
        body = convert_inline_markdown(Regexp.last_match(1))
        stash_expression("#link(#{typst_string(Regexp.last_match(2))})[#{body}]")
      end
    end

    # Converts emphasis and escapes everything else, so whatever is left of
    # the Markdown reads as literal text in Typst.
    def convert_inline_markdown(text)
      # Convert combined bold+italic first: ***text*** and ___text___ are a
      # single Markdown token, and letting the bold pass see them would consume
      # only two of the three markers and strand the leftover one mid-word.
      # ***text*** -> *_text_*
      #
      # As in Markdown, an opening marker must be followed, and a closing one
      # preceded, by non-whitespace, so "2 * 3 * 4" is not emphasis.
      text = text.gsub(/(\*\*\*|___)(?=\S)(.+?)(?<=\S)\1/, "#{BOLD_OPEN}#{ITALIC_OPEN}\\2#{ITALIC_CLOSE}#{BOLD_CLOSE}")

      # **text** or __text__ -> *text*
      text = text.gsub(/(\*\*|__)(?=\S)(.+?)(?<=\S)\1/, "#{BOLD_OPEN}\\2#{BOLD_CLOSE}")

      # *text* or _text_ -> _text_
      text = text.gsub(/(?<!\*)\*(?![\s*])(.+?)(?<![\s*])\*(?!\*)/, "#{ITALIC_OPEN}\\1#{ITALIC_CLOSE}")
      text = text.gsub(/(?<!_)_(?![\s_])(.+?)(?<![\s_])_(?!_)/, "#{ITALIC_OPEN}\\1#{ITALIC_CLOSE}")

      # A literal slash before a bold marker would open a /* comment.
      text = escape_typst(text).gsub(%r{/(?=#{BOLD_OPEN}|#{BOLD_CLOSE})}, "\\\\/")

      text.tr("#{BOLD_OPEN}#{BOLD_CLOSE}#{ITALIC_OPEN}#{ITALIC_CLOSE}", "**__")
    end

    # @return [String] a placeholder for +markup+, which {#restore_stash}
    #   swaps back in
    def stash(markup, literal)
      @tokens << StashedToken.new(markup, literal)
      "#{STASH_OPEN}#{@tokens.length - 1}#{STASH_CLOSE}"
    end

    def stash_expression(markup)
      stash("#{markup}#{EXPRESSION_END}", markup)
    end

    # Puts stashed markup back, then ends each embedded expression where the
    # text after it would otherwise continue it.
    def restore_stash(text)
      expand_stash(text).gsub(/#{EXPRESSION_END}(?=\(|\.[\p{L}_])/, ";").delete(EXPRESSION_END)
    end

    # Swaps placeholders for their markup, including any stashed inside other
    # markup, such as code in a link's text.
    def expand_stash(text)
      text.gsub(STASH_PATTERN) { expand_stash(@tokens[Regexp.last_match(1).to_i].markup) }
    end

    # Writes +text+ as a Typst string literal. Stashed pieces inside it, such
    # as a backslash escape in a URL, stand for their source text there.
    def typst_string(text)
      literal = text.gsub(STASH_PATTERN) { @tokens[Regexp.last_match(1).to_i].literal }

      "\"#{literal.gsub(/[\\"]/) { |char| "\\#{char}" }}\""
    end

    # MARK: - Placeholder handling

    # Stashes any of this class's sentinel characters that the caller's input
    # already contained, so the emphasis passes cannot mistake them for markers
    # they wrote themselves.
    #
    # Each occurrence is replaced by LITERAL_PLACEHOLDER and its original
    # character recorded, in order, on +@placeholder_literals+.
    #
    # @param text [String] the source text
    # @return [String] the text with pre-existing sentinels stashed
    def protect_placeholder_bytes(text)
      @placeholder_literals = []
      return text unless text.match?(PLACEHOLDER_PATTERN)

      text.gsub(PLACEHOLDER_PATTERN) do |char|
        @placeholder_literals << char
        LITERAL_PLACEHOLDER
      end
    end

    # Puts back the characters stashed by {#protect_placeholder_bytes}, in the
    # order they were found.
    #
    # @param text [String] the converted text
    # @return [String] the text with the caller's original characters restored
    def restore_placeholder_bytes(text)
      return text if @placeholder_literals.empty?

      index = -1
      text.gsub(LITERAL_PLACEHOLDER) { @placeholder_literals[index += 1] }
    end
  end
end
