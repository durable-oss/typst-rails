# frozen_string_literal: true

require "test_helper"
require "pathname"

module TypstRails
  class RendererRootPathTest < Minitest::Test
    include TestHelpers

    def setup
      @root = Dir.mktmpdir("typst_rails_root_test_")
    end

    def teardown
      TypstRails.configuration = nil
      FileUtils.remove_entry(@root) if @root && File.exist?(@root)
    end

    def test_compiles_with_the_configured_root
      TypstRails.configure { |c| c.default_root_path = @root }

      root, typ_path = capture_compile_args { Renderer.new("= Test").render(nil, { a: 1 }) }

      assert_equal File.expand_path(@root), root
      assert typ_path.start_with?("#{File.expand_path(@root)}/"), "template must be inside the root"
    end

    def test_accepts_a_pathname
      TypstRails.configure { |c| c.default_root_path = Pathname.new(@root) }

      root, = capture_compile_args { Renderer.new("= Test").render(nil, {}) }

      assert_equal File.expand_path(@root), root
    end

    def test_data_file_sits_next_to_the_template
      TypstRails.configure { |c| c.default_root_path = @root }
      data_path = nil
      backend = stub("backend")
      backend.stubs(:compile).with do |typ_path, _root|
        data_path = File.join(File.dirname(typ_path), "typst_data.json")
        File.exist?(data_path)
      end.returns("pdf")
      Backends::Registry.stubs(:resolve).returns(backend)

      Renderer.new('#json("typst_data.json")').render(nil, { a: 1 })

      refute_nil data_path
    end

    def test_removes_its_working_directory_from_the_root
      TypstRails.configure { |c| c.default_root_path = @root }

      capture_compile_args { Renderer.new("= Test").render(nil, { a: 1 }) }

      assert_empty Dir.children(@root)
    end

    def test_missing_root_raises_a_typst_rails_error
      TypstRails.configure { |c| c.default_root_path = File.join(@root, "missing") }

      error = assert_raises(Error) { Renderer.new("= Test").render(nil, {}) }

      assert_includes error.message, "default_root_path"
    end

    def test_without_a_configured_root_the_run_directory_is_the_root
      root, typ_path = capture_compile_args { Renderer.new("= Test").render(nil, {}) }

      assert_equal File.dirname(typ_path), root
    end

    def test_template_can_load_files_from_the_root
      skip "typst CLI not installed" unless Backends::Cli.new.available?

      File.write(File.join(@root, "greeting.txt"), "hello from the root")
      TypstRails.configure do |c|
        c.default_root_path = @root
        c.backend = :cli
      end

      pdf = Renderer.new('#read("/greeting.txt")').render(nil, {})

      assert pdf.start_with?("%PDF")
    end

    private

    def capture_compile_args
      args = nil
      backend = stub("backend")
      backend.stubs(:compile).with { |typ_path, root| args = [root, typ_path] }.returns("pdf")
      Backends::Registry.stubs(:resolve).returns(backend)
      yield
      args
    end
  end
end
