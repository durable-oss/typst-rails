# frozen_string_literal: true

require "test_helper"
require "date"
require "tmpdir"

module TypstRails
  # Compiles real Typst documents, so the output of the helpers is checked by
  # Typst's own parser rather than against the strings we expect to produce.
  #
  # Every assertion about the document is made in Typst itself, with
  # #assert.eq: if the markup does not mean what we think it means, the
  # compile fails and the Typst diagnostic becomes the test failure.
  #
  # These run against whichever backend Registry auto-detection picks (the
  # `typst` gem or the CLI), and skip when neither is installed.
  class TypstCompilationTest < Minitest::Test
    include Helpers

    # Flattens content to a string, failing on any element other than text,
    # spaces, smart quotes and the symbols Typst makes of backslash escapes.
    # Escaped text must come back as nothing but literal text, so an
    # emphasis, heading or code expression slipping through panics.
    PLAIN_TEXT_FUNCTION = <<~'TYP'
      #let plain(c) = {
        if type(c) == str { c }
        else if c.func() == text { c.text }
        else if repr(c.func()) == "symbol" { c.text }
        else if c.func() == [ ].func() { " " }
        else if c.func() == smartquote { if c.at("double", default: true) { "\"" } else { "'" } }
        else if c.has("children") { c.children.map(plain).join("") }
        else { panic("not plain text: " + repr(c)) }
      }
    TYP

    def setup
      @original_configuration = TypstRails.configuration
      TypstRails.configuration = Configuration.new

      Backends::Registry.resolve
    rescue Error
      skip "no Typst backend is installed"
    end

    def teardown
      TypstRails.configuration = @original_configuration
    end

    # MARK: - Rendering

    def test_render_returns_a_pdf
      pdf = render_typst("= Hello")

      assert pdf.start_with?("%PDF-"), "Expected PDF bytes, got #{pdf[0, 20].inspect}"
    end

    def test_local_assigns_reach_the_template_as_json
      render_typst(<<~TYP, { title: "Report", count: 3, ratio: 0.5, draft: false, missing: nil, tags: %w[a b] })
        #let data = json("typst_data.json")
        #assert.eq(data.title, "Report")
        #assert.eq(data.count, 3)
        #assert.eq(data.ratio, 0.5)
        #assert.eq(data.draft, false)
        #assert.eq(data.missing, none)
        #assert.eq(data.tags, ("a", "b"))
      TYP
    end

    def test_view_context_assigns_and_locals_reach_the_template
      view_context = Struct.new(:assigns).new({ "title" => "From assigns", "due" => Date.new(2026, 1, 15) })

      render_typst(<<~TYP, { title: "From locals" }, view_context: view_context)
        #let data = json("typst_data.json")
        #assert.eq(data.title, "From locals")
        #assert.eq(data.due, "2026-01-15")
      TYP
    end

    def test_nested_data_keeps_its_structure
      render_typst(<<~TYP, { items: [{ name: "Widget", price: 9.5 }, { name: "Gadget", price: 12 }] })
        #let data = json("typst_data.json")
        #assert.eq(data.items.len(), 2)
        #assert.eq(data.items.at(1).name, "Gadget")
        #assert.eq(data.items.map(i => i.price).sum(), 21.5)
      TYP
    end

    def test_rendering_without_data_writes_no_data_file
      error = assert_render_fails { render_typst("#json(\"typst_data.json\")") }

      assert_match(/typst_data\.json/, error.message)
    end

    def test_typst_errors_surface_as_typst_rails_errors
      error = assert_render_fails { render_typst("#undefined_function()") }

      assert_match(/unknown variable/, error.message)
    end

    # MARK: - escape_typst

    def test_escaped_text_reads_back_as_the_original_text
      cases = [
        "Hello #world", "#set text(red)", "Price: $100", "$x^2$", "a*b*c", "*not bold*",
        "snake_case_name", "_not italic_", "[link]", "back\\slash", "<label>", "{code}",
        "me@example.com", "@ref", "`raw`", "a~b", "a // not a comment", "a /* nor this */ b",
        "a -- b --- c -? d", "= Not a heading", "- not a list", "+ not numbered",
        "/ Not: a term", "1. not numbered", "3.14 is pi", "\"quoted\" and 'single'",
        "café ünïcödé", "50% off & more"
      ]

      assert_reads_back_as_plain_text(cases)
    end

    def test_escaped_line_start_markers_read_back_on_every_line
      assert_reads_back_as_plain_text(["= one\n- two\n+ three\n/ four: x\n5. five"])
    end

    # Without this, a plain() that accepted anything would pass every escape
    # test above.
    def test_unescaped_markup_is_caught_by_the_plain_text_check
      ["*bold*", "= Heading", "#emph[x]", "<label>", "`raw`"].each do |markup|
        assert_render_fails("Expected #{markup.inspect} to be rejected") do
          compile_plain_text_cases([markup], [markup])
        end
      end
    end

    # MARK: - markdown_to_typst

    def test_markdown_headings_become_typst_headings
      assert_markdown_compiles("# One\n\n## Two\n\n###### Six", <<~TYP)
        #context {
          let headings = query(heading)
          assert.eq(headings.map(h => h.level), (1, 2, 6))
          assert.eq(headings.map(h => plain(h.body)), ("One", "Two", "Six"))
        }
      TYP
    end

    def test_markdown_bold_and_italic_become_strong_and_emph
      assert_markdown_compiles("**bold** and *italic* and _also_", <<~TYP)
        #context {
          assert.eq(query(strong).map(s => plain(s.body)), ("bold",))
          assert.eq(query(emph).map(e => plain(e.body)), ("italic", "also"))
        }
      TYP
    end

    def test_markdown_bold_italic_becomes_emph_inside_strong
      assert_markdown_compiles("***both***", <<~TYP)
        #context {
          let bold = query(strong)
          assert.eq(bold.len(), 1)
          assert.eq(bold.first().body.func(), emph)
          assert.eq(plain(bold.first().body.body), "both")
        }
      TYP
    end

    def test_markdown_links_keep_their_destination_and_text
      assert_markdown_compiles("See [Typst docs](https://typst.app/docs/) and [*this*](https://example.com/a_b_c)", <<~TYP)
        #context {
          let links = query(link)
          assert.eq(links.map(l => l.dest), ("https://typst.app/docs/", "https://example.com/a_b_c"))
          assert.eq(plain(links.first().body), "Typst docs")
          assert.eq(links.last().body.func(), emph)
        }
      TYP
    end

    def test_markdown_code_stays_raw
      assert_markdown_compiles("Use `**not bold**` here\n\n```\n# not a heading\n#let x = 1\n```", <<~'TYP')
        #context {
          let code = query(raw)
          assert.eq(code.map(r => r.text), ("**not bold**", "# not a heading\n#let x = 1"))
          assert.eq(code.map(r => r.block), (false, true))
          assert.eq(query(heading).len(), 0)
          assert.eq(query(strong).len(), 0)
        }
      TYP
    end

    def test_markdown_arithmetic_asterisks_stay_plain_text
      assert_markdown_compiles("2 * 3 * 4", <<~TYP)
        #context assert.eq(query(emph).len(), 0)
      TYP
    end

    def test_markdown_prose_with_typst_syntax_reads_back_as_plain_text
      cases = [
        "Use #hashtag", "#read(\"secret.txt\")", "Costs $5 or $10", "Price: 5 $", "me@example.com",
        "a < b > c", "{braces}", "C:\\path\\file", "2 * 3 * 4", "a _ b", "**unclosed",
        "= not a heading", "/ not a term", "-5 degrees", "a // b /* c", "x -- y", "it`s", "~tilde~"
      ]

      compile_plain_text_cases(cases.map { |text| markdown_to_typst(text) }, cases)
    end

    def test_markdown_backslash_escapes_read_back_as_their_characters
      compile_plain_text_cases(
        [markdown_to_typst("\\*not italic\\* \\# \\[x\\](u) \\\\ \\_")],
        ["*not italic* # [x](u) \\ _"]
      )
    end

    def test_markdown_bullets_become_list_items
      assert_markdown_compiles("* one\n+ two\n- three\n\n1. first\n2) second", <<~TYP)
        #context {
          assert.eq(query(list).map(l => l.children.map(i => plain(i.body))), (("one", "two", "three"),))
          assert.eq(query(enum).map(e => e.children.map(i => plain(i.body))), (("first", "second"),))
        }
      TYP
    end

    def test_markdown_link_urls_with_quotes_stay_inside_the_string
      assert_markdown_compiles('[x](https://e.com/?q="hi") [y](a"+read("secret.txt")+")', <<~'TYP')
        #context {
          assert.eq(query(link).map(l => l.dest), ("https://e.com/?q=\"hi\"", "a\"+read(\"secret.txt\""))
        }
      TYP
    end

    def test_markdown_link_titles_are_dropped
      assert_markdown_compiles('[x](https://typst.app "The title")', <<~TYP)
        #context assert.eq(query(link).map(l => l.dest), ("https://typst.app",))
      TYP
    end

    def test_markdown_autolinks_become_links
      assert_markdown_compiles("<https://typst.app>", <<~TYP)
        #context assert.eq(query(link).map(l => l.dest), ("https://typst.app",))
      TYP
    end

    def test_text_after_a_markdown_link_is_not_read_as_part_of_it
      assert_markdown_compiles("[a](u)(note) and [b](v).field and [c](w). End", <<~TYP)
        #context assert.eq(query(link).map(l => plain(l.body)), ("a", "b", "c"))
      TYP
    end

    def test_a_slash_before_markdown_bold_does_not_open_a_comment
      assert_markdown_compiles("and/**or** after", <<~TYP)
        #context assert.eq(query(strong).map(s => plain(s.body)), ("or",))
      TYP
    end

    # MARK: - html_to_typst

    # ReverseMarkdown backslash-escapes Markdown characters in text, so these
    # come through as Markdown escapes rather than raw Typst syntax.
    def test_html_text_with_typst_syntax_reads_back_as_plain_text
      text = "Ticket #42 costs $5 * 2 for me@example.com"

      compile_plain_text_cases([html_to_typst("<p>#{text}</p>").strip], [text])
    end

    def test_html_converts_to_equivalent_typst_structure
      typst = html_to_typst("<h1>Title</h1><p><strong>Bold</strong> and <a href=\"https://typst.app\">a link</a></p>")

      compile_with_prelude(<<~TYP)
        #{typst}

        #context {
          assert.eq(query(heading).map(h => plain(h.body)), ("Title",))
          assert.eq(query(strong).map(s => plain(s.body)), ("Bold",))
          assert.eq(query(link).map(l => l.dest), ("https://typst.app",))
        }
      TYP
    end

    private

    def render_typst(source, data = {}, view_context: nil)
      Renderer.new(source).render(view_context, data)
    end

    def compile_with_prelude(source, data = {})
      render_typst(PLAIN_TEXT_FUNCTION + source, data)
    end

    def assert_reads_back_as_plain_text(cases)
      expected = cases.map { |text| text.split("\n").join(" ") }

      compile_plain_text_cases(cases.map { |text| escape_typst(text) }, expected)
    end

    # Each case sits on its own lines inside a content block, so line-start
    # markers are at the start of a line, as they would be in a template.
    def compile_plain_text_cases(markup_cases, expected)
      blocks = markup_cases.map { |markup| "[\n#{markup}\n]" }.join(",\n")

      compile_with_prelude(<<~TYP, { expected: expected })
        #let data = json("typst_data.json")
        #let cases = (#{blocks},)
        #for (i, c) in cases.enumerate() {
          assert.eq(plain(c).trim(), data.expected.at(i), message: "case " + str(i))
        }
      TYP
    end

    # The renderer logs each failure before raising; keep that out of the
    # test output.
    def assert_render_fails(message = nil, &block)
      error = nil

      capture_io { error = assert_raises(Error, message, &block) }
      error
    end

    def assert_markdown_compiles(markdown, assertions)
      compile_with_prelude("#{markdown_to_typst(markdown)}\n\n#{assertions}")
    end
  end

  module Backends
    # Drives the CLI backend against a real `typst` executable, to check the
    # command line it builds is one Typst accepts. CliTest covers the same
    # paths with fake executables.
    class CliCompilationTest < Minitest::Test
      def setup
        @original_configuration = TypstRails.configuration
        TypstRails.configuration = Configuration.new
        @backend = Cli.new

        skip "the typst CLI is not on PATH" unless @backend.available?
      end

      def teardown
        TypstRails.configuration = @original_configuration
      end

      def test_compile_returns_a_pdf
        in_typst_project("= Hello") do |typ_path, root|
          assert @backend.compile(typ_path, root).start_with?("%PDF-")
        end
      end

      def test_compile_resolves_relative_files_against_the_root
        in_typst_project("#let data = json(\"data.json\")\n#assert.eq(data.name, \"root\")") do |typ_path, root|
          File.write(File.join(root, "data.json"), '{"name": "root"}')

          assert @backend.compile(typ_path, root).start_with?("%PDF-")
        end
      end

      def test_compile_failure_includes_the_typst_diagnostic
        in_typst_project("#undefined_function()") do |typ_path, root|
          error = assert_raises(Error) { @backend.compile(typ_path, root) }

          assert_match(/unknown variable: undefined_function/, error.message)
        end
      end

      def test_compile_leaves_only_the_source_behind
        in_typst_project("= Hello") do |typ_path, root|
          @backend.compile(typ_path, root)

          assert_equal ["doc.typ"], Dir.children(root)
        end
      end

      private

      def in_typst_project(source)
        Dir.mktmpdir do |root|
          typ_path = File.join(root, "doc.typ")
          File.write(typ_path, source)
          yield typ_path, root
        end
      end
    end
  end
end
