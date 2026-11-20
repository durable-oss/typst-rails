# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"
require "fileutils"
require "pathname"

module TypstRails
  class TemplateRenderingTest < Minitest::Test
    # Records what #attach received, standing in for an ActiveStorage
    # attachment.
    class FakeAttachable
      attr_reader :attached

      def attach(io:, filename:, content_type:)
        @attached = { body: io.read, filename: filename, content_type: content_type }
        :attached
      end
    end

    def setup
      @root = Dir.mktmpdir("typst_templates")
    end

    def teardown
      FileUtils.remove_entry(@root) if @root && File.directory?(@root)
    end

    # MARK: - Template resolution

    def test_resolves_a_name_without_the_extension
      path = write_template("reports/monthly.typ", "= Monthly")

      assert_equal path, TemplateRendering.resolve("reports/monthly", @root)
    end

    def test_resolves_a_name_with_the_extension
      path = write_template("reports/monthly.typ", "= Monthly")

      assert_equal path, TemplateRendering.resolve("reports/monthly.typ", @root)
    end

    def test_falls_back_to_the_rails_style_pdf_typ_name
      path = write_template("reports/monthly.pdf.typ", "= Monthly")

      assert_equal path, TemplateRendering.resolve("reports/monthly", @root)
    end

    def test_prefers_name_typ_over_name_pdf_typ
      path = write_template("reports/monthly.typ", "= Plain")
      write_template("reports/monthly.pdf.typ", "= Rails")

      assert_equal path, TemplateRendering.resolve("reports/monthly", @root)
    end

    def test_accepts_a_pathname_root
      path = write_template("a.typ", "= A")

      assert_equal path, TemplateRendering.resolve("a", Pathname.new(@root))
    end

    def test_uses_an_absolute_path_as_given
      Dir.mktmpdir("elsewhere") do |elsewhere|
        path = File.join(elsewhere, "invoice.typ")
        File.write(path, "= Invoice")

        assert_equal path, TemplateRendering.resolve(path, @root)
      end
    end

    def test_rejects_parent_directory_traversal
      Dir.mktmpdir("outside") do |outside|
        File.write(File.join(outside, "secret.typ"), "= Secret")
        relative = File.join("..", File.basename(outside), "secret")

        error = assert_raises(ArgumentError) { TemplateRendering.resolve(relative, @root) }

        assert_match(/outside the template root/, error.message)
      end
    end

    def test_rejects_traversal_that_climbs_out_after_descending
      write_template("reports/monthly.typ", "= Monthly")

      assert_raises(ArgumentError) { TemplateRendering.resolve("reports/../../etc/passwd", @root) }
    end

    def test_rejects_a_sibling_directory_sharing_the_root_prefix
      sibling = "#{@root}-sibling"
      FileUtils.mkdir_p(sibling)
      File.write(File.join(sibling, "x.typ"), "= X")

      assert_raises(ArgumentError) do
        TemplateRendering.resolve(File.join("..", File.basename(sibling), "x"), @root)
      end
    ensure
      FileUtils.rm_rf(sibling)
    end

    def test_rejects_a_home_directory_name
      assert_raises(ArgumentError) { TemplateRendering.resolve("~/report", @root) }
    end

    def test_allows_dot_segments_that_stay_inside_the_root
      path = write_template("monthly.typ", "= Monthly")

      assert_equal path, TemplateRendering.resolve("reports/../monthly", @root)
    end

    def test_rejects_a_blank_name
      assert_raises(ArgumentError) { TemplateRendering.resolve(" ", @root) }
    end

    def test_missing_template_raises_typst_error_listing_the_paths_tried
      error = assert_raises(Error) { TemplateRendering.resolve("nope", @root) }

      assert_includes error.message, File.join(@root, "nope.typ")
      assert_includes error.message, File.join(@root, "nope.pdf.typ")
    end

    def test_a_directory_is_not_a_template
      FileUtils.mkdir_p(File.join(@root, "dir.typ"))

      assert_raises(Error) { TemplateRendering.resolve("dir", @root) }
    end

    # MARK: - Default root

    def test_default_root_is_the_current_directory_without_rails
      assert_equal Dir.pwd, TemplateRendering.default_root
    end

    def test_default_root_is_app_views_under_rails
      rails = Module.new
      rails.define_singleton_method(:application) { :app }
      rails.define_singleton_method(:root) { Pathname.new("/srv/app") }

      with_defined_constant(:Rails, rails) do
        assert_equal "/srv/app/app/views", TemplateRendering.default_root
      end
    end

    def test_default_root_falls_back_to_the_current_directory_when_rails_root_is_nil
      rails = Module.new
      rails.define_singleton_method(:application) { :app }
      rails.define_singleton_method(:root) { nil }

      with_defined_constant(:Rails, rails) do
        assert_equal Dir.pwd, TemplateRendering.default_root
      end
    end

    def test_render_resolves_against_the_default_root
      write_template("cwd.typ", "= Here")
      mock_successful_typst_compilation(pdf_content: "cwd pdf")

      Dir.chdir(@root) do
        assert_equal "cwd pdf", TypstRails.render("cwd")
      end
    end

    # MARK: - TypstRails.render

    def test_render_returns_the_pdf
      write_template("hello.typ", "= Hello")
      mock_successful_typst_compilation(pdf_content: "hello pdf")

      assert_equal "hello pdf", TypstRails.render("hello", root: @root)
    end

    def test_render_runs_erb_with_locals_assigns_and_helpers
      write_template("greet.typ", "= <%= @title %>: <%= escape_typst(note) %>")
      captured = capture_rendered_source

      TypstRails.render("greet", root: @root, locals: { note: "#1" }, assigns: { title: "Report" })

      assert_equal "= Report: \\#1", captured.call
    end

    def test_render_accepts_string_keys
      write_template("greet.typ", "<%= @title %> <%= note %>")
      captured = capture_rendered_source

      TypstRails.render("greet", root: @root, locals: { "note" => "n" }, assigns: { "title" => "t" })

      assert_equal "t n", captured.call
    end

    def test_render_writes_locals_and_assigns_to_the_data_file
      write_template("data.typ", '#let data = json("typst_data.json")')
      data = capture_data_file

      TypstRails.render("data", root: @root,
                                locals: { total: 42, shared: "local" },
                                assigns: { title: "Report", shared: "assign" })

      assert_equal({ "title" => "Report", "shared" => "local", "total" => 42 }, data.call)
    end

    def test_render_converts_dates_in_the_data_file
      write_template("data.typ", '#let data = json("typst_data.json")')
      data = capture_data_file

      TypstRails.render("data", root: @root, locals: { on: Date.new(2026, 11, 20) })

      assert_equal({ "on" => "2026-11-20" }, data.call)
    end

    def test_render_rejects_non_hash_locals
      assert_raises(ArgumentError) { TypstRails.render("x", root: @root, locals: [1]) }
    end

    def test_render_rejects_non_hash_assigns
      assert_raises(ArgumentError) { TypstRails.render("x", root: @root, assigns: "x") }
    end

    def test_render_rejects_traversal_before_reading_anything
      File.expects(:read).never

      assert_raises(ArgumentError) { TypstRails.render("../../etc/passwd", root: @root) }
    end

    def test_render_propagates_compilation_errors
      write_template("bad.typ", "#bad()")
      mock_failed_typst_compilation(stderr: "unknown variable")

      assert_raises(Error) { TypstRails.render("bad", root: @root) }
    end

    # MARK: - TypstRails.render_and_attach

    def test_render_and_attach_attaches_the_pdf
      write_template("hello.typ", "= Hello")
      mock_successful_typst_compilation(pdf_content: "attached pdf")
      attachable = FakeAttachable.new

      result = TypstRails.render_and_attach(attachable, "hello", filename: "hello.pdf", root: @root)

      assert_equal :attached, result
      assert_equal({ body: "attached pdf", filename: "hello.pdf", content_type: "application/pdf" },
                   attachable.attached)
    end

    def test_render_and_attach_passes_locals_assigns_and_content_type
      write_template("greet.typ", "<%= @title %> <%= note %>")
      captured = capture_rendered_source
      attachable = FakeAttachable.new

      TypstRails.render_and_attach(attachable, "greet",
                                   filename: "g.pdf", root: @root, content_type: "application/x-pdf",
                                   locals: { note: "n" }, assigns: { title: "t" })

      assert_equal "t n", captured.call
      assert_equal "application/x-pdf", attachable.attached[:content_type]
    end

    def test_render_and_attach_rejects_objects_without_attach
      error = assert_raises(ArgumentError) do
        TypstRails.render_and_attach(Object.new, "hello", filename: "x.pdf", root: @root)
      end

      assert_match(/does not respond to attach/, error.message)
    end

    def test_render_and_attach_does_not_attach_when_rendering_fails
      attachable = FakeAttachable.new

      assert_raises(Error) { TypstRails.render_and_attach(attachable, "missing", filename: "x.pdf", root: @root) }
      assert_nil attachable.attached
    end

    # MARK: - Scope

    def test_scope_skips_names_that_are_not_valid_instance_variables
      scope = TemplateRendering::Scope.new("ok" => 1, "not-ok" => 2)

      assert_equal [:@ok], scope.instance_variables
    end

    private

    def write_template(relative, content)
      path = File.join(@root, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      path
    end

    # Stubs the Renderer and returns a lambda yielding the source it got.
    def capture_rendered_source
      captured = nil
      renderer = mock("renderer")
      renderer.stubs(:render).returns("pdf")
      Renderer.stubs(:new).with { |src| captured = src }.returns(renderer)
      -> { captured }
    end

    # Stubs the backend and returns a lambda yielding the parsed
    # typst_data.json it saw.
    def capture_data_file
      data = nil
      backend = stub("backend")
      backend.stubs(:compile).with do |typ_path, _root|
        data = JSON.parse(File.read(File.join(File.dirname(typ_path), "typst_data.json")))
      end.returns("pdf")
      Backends::Registry.stubs(:resolve).returns(backend)
      -> { data }
    end
  end

  # Compiles real templates, so it skips when no Typst backend is installed.
  class TemplateRenderingCompilationTest < Minitest::Test
    def setup
      @original_configuration = TypstRails.configuration
      TypstRails.configuration = Configuration.new
      @root = Dir.mktmpdir("typst_templates")

      Backends::Registry.resolve
    rescue Error
      skip "no Typst backend is installed"
    end

    def teardown
      TypstRails.configuration = @original_configuration
      FileUtils.remove_entry(@root) if @root && File.directory?(@root)
    end

    def test_render_compiles_a_template_with_erb_and_data
      FileUtils.mkdir_p(File.join(@root, "reports"))
      File.write(File.join(@root, "reports", "monthly.typ"), <<~TYP)
        #let data = json("typst_data.json")
        #assert.eq(data.month, "October")
        #assert.eq(data.title, "Report")
        = <%= @title %> for <%= escape_typst(month) %>
      TYP

      pdf = TypstRails.render("reports/monthly", root: @root,
                                                 locals: { month: "October" }, assigns: { title: "Report" })

      assert pdf.start_with?("%PDF-"), "Expected PDF bytes, got #{pdf[0, 20].inspect}"
      assert_equal Encoding::BINARY, pdf.encoding
    end

    def test_render_and_attach_attaches_a_real_pdf
      File.write(File.join(@root, "hello.typ"), "= Hello")
      attachable = TemplateRenderingTest::FakeAttachable.new

      TypstRails.render_and_attach(attachable, "hello", filename: "hello.pdf", root: @root)

      assert attachable.attached[:body].start_with?("%PDF-")
    end
  end
end
