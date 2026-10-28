# frozen_string_literal: true

require "test_helper"

module TypstRails
  class RendererTest < Minitest::Test
    def test_initialize_with_string_source
      source = "= Hello World"
      renderer = Renderer.new(source)

      assert_equal source, renderer.source
    end

    def test_initialize_with_non_string_source
      renderer = Renderer.new(123)

      assert_equal "123", renderer.source
    end

    def test_render_without_view_context
      source = "= Test Document"
      renderer = Renderer.new(source)

      mock_successful_typst_compilation(pdf_content: "test pdf")

      result = renderer.render(nil, { title: "Test" })

      assert_equal "test pdf", result
    end

    def test_render_with_view_context
      source = "= Test Document"
      renderer = Renderer.new(source)
      view_context = mock_view_context({ name: "Test" })

      mock_successful_typst_compilation

      result = renderer.render(view_context, { title: "Report" })

      refute_nil result
    end

    def test_render_with_empty_data
      source = "= Simple Document"
      renderer = Renderer.new(source)

      mock_successful_typst_compilation

      result = renderer.render(nil, {})

      refute_nil result
    end

    def test_render_creates_json_data_file_when_data_present
      source = "= Test"
      renderer = Renderer.new(source)
      data = { title: "My Title", count: 42 }

      # Track file operations
      json_written = nil
      File.expects(:write).with do |path, content|
        json_written = JSON.parse(content) if path.end_with?("typst_data.json")
        true
      end

      mock_successful_typst_compilation

      renderer.render(nil, data)

      assert_equal data.transform_keys(&:to_s), json_written
    end

    def test_render_does_not_create_json_file_when_data_empty
      source = "= Test"
      renderer = Renderer.new(source)

      File.expects(:write).with do |path, _|
        path.end_with?("typst_data.json")
      end.never

      mock_successful_typst_compilation

      renderer.render(nil, {})
    end

    def test_render_cleans_up_temp_files_on_success
      root = capture_compile_root { Renderer.new("= Test").render(nil, { title: "T" }) }

      refute_path_exists root, "temp directory #{root} should be removed"
    end

    def test_render_cleans_up_temp_files_on_failure
      root = nil
      backend = stub("backend")
      backend.stubs(:compile).with { |_typ, dir| root = dir }.raises(Error, "boom")
      Backends::Registry.stubs(:resolve).returns(backend)

      assert_raises(Error) { Renderer.new("= Test").render(nil, { title: "T" }) }

      refute_path_exists root, "temp directory should be removed even on failure"
    end

    # Each render gets its own directory, so concurrent renders cannot read
    # or delete one another's typst_data.json.
    def test_each_render_uses_its_own_directory
      roots = Array.new(2) { capture_compile_root { Renderer.new("= Test").render(nil, { a: 1 }) } }

      refute_equal roots[0], roots[1]
    end

    # Each template's source names its render, so a render that reads
    # another's typst_data.json is caught by comparing the two.
    def test_concurrent_renders_see_only_their_own_data
      seen = Queue.new
      backend = Class.new(Backends::Base) do
        define_method(:compile) do |typ_path, root|
          sleep 0.01 # let the other renders write their data first
          seen << [File.read(typ_path), JSON.parse(File.read(File.join(root, "typst_data.json")))["id"]]
          "pdf"
        end
      end.new
      Backends::Registry.stubs(:resolve).returns(backend)

      Array.new(8) { |i| Thread.new { Renderer.new(i.to_s).render(nil, { id: i }) } }.each(&:join)

      results = Array.new(seen.size) { seen.pop }

      assert_equal 8, results.size
      results.each { |source, id| assert_equal source, id.to_s, "render #{source} read render #{id}'s data" }
    end

    def test_render_raises_error_on_compilation_failure
      source = "= Test"
      renderer = Renderer.new(source)

      mock_failed_typst_compilation(stderr: "syntax error on line 5")

      error = assert_raises(Error) do
        renderer.render(nil, {})
      end

      assert_includes error.message, "Typst compilation failed"
      assert_includes error.message, "syntax error on line 5"
    end

    def test_transform_value_for_json_serialization_with_date
      renderer = Renderer.new("test")
      date = Date.new(2025, 1, 15)
      result = renderer.send(:transform_value_for_json_serialization, date)

      assert_equal "2025-01-15", result
    end

    def test_transform_value_for_json_serialization_with_time
      renderer = Renderer.new("test")
      time = Time.new(2025, 1, 15, 10, 30, 45)
      result = renderer.send(:transform_value_for_json_serialization, time)

      assert_match(/2025-01-15T10:30:45/, result)
    end

    def test_transform_value_for_json_serialization_with_datetime
      renderer = Renderer.new("test")
      datetime = DateTime.new(2025, 1, 15, 10, 30, 45)
      result = renderer.send(:transform_value_for_json_serialization, datetime)

      assert_match(/2025-01-15T10:30:45/, result)
    end

    def test_transform_value_for_json_serialization_with_array
      renderer = Renderer.new("test")
      array = [1, "test", Date.new(2025, 1, 15)]
      result = renderer.send(:transform_value_for_json_serialization, array)

      assert_equal 1, result[0]
      assert_equal "test", result[1]
      assert_equal "2025-01-15", result[2]
    end

    def test_transform_value_for_json_serialization_with_hash
      renderer = Renderer.new("test")
      hash = { name: "Test", date: Date.new(2025, 1, 15) }
      result = renderer.send(:transform_value_for_json_serialization, hash)

      assert_equal "Test", result[:name]
      assert_equal "2025-01-15", result[:date]
    end

    def test_transform_value_for_json_serialization_with_nested_structures
      renderer = Renderer.new("test")
      data = {
        items: [
          { name: "Item 1", created_at: Date.new(2025, 1, 15) },
          { name: "Item 2", created_at: Date.new(2025, 1, 16) }
        ]
      }
      result = renderer.send(:transform_value_for_json_serialization, data)

      assert_equal "2025-01-15", result[:items][0][:created_at]
      assert_equal "2025-01-16", result[:items][1][:created_at]
    end

    def test_transform_value_for_json_serialization_with_active_record_object
      renderer = Renderer.new("test")

      active_record_module = Module.new
      base_class = Class.new do
        def as_json
          { "id" => 1, "name" => "Widget" }
        end
      end
      active_record_module.const_set(:Base, base_class)
      record = base_class.new

      with_defined_constant(:ActiveRecord, active_record_module) do
        result = renderer.send(:transform_value_for_json_serialization, record)

        assert_equal({ "id" => 1, "name" => "Widget" }, result)
      end
    end

    def test_collect_data_for_typst_with_view_context
      renderer = Renderer.new("test")
      view_context = mock_view_context({ user: "John" })
      locals = { title: "Report" }

      data = renderer.send(:collect_data_for_typst, view_context, locals)

      assert_equal "John", data[:user]
      assert_equal "Report", data[:title]
    end

    def test_collect_data_for_typst_locals_override_assigns
      renderer = Renderer.new("test")
      view_context = mock_view_context({ title: "Original" })
      locals = { title: "Override" }

      data = renderer.send(:collect_data_for_typst, view_context, locals)

      assert_equal "Override", data[:title]
    end

    def test_collect_data_for_typst_with_view_context_without_assigns
      renderer = Renderer.new("test")
      view_context = Object.new
      locals = { title: "Report" }

      data = renderer.send(:collect_data_for_typst, view_context, locals)

      assert_equal "Report", data[:title]
      refute data.key?(:user)
    end

    def test_method_missing_delegates_to_view_context
      renderer = Renderer.new("test")
      view_context = mock("view_context")
      view_context.expects(:some_helper).with("arg").returns("result")

      renderer.instance_variable_set(:@view_context, view_context)

      assert_equal "result", renderer.send(:some_helper, "arg")
    end

    def test_method_missing_raises_when_view_context_doesnt_respond
      renderer = Renderer.new("test")
      view_context = Object.new
      renderer.instance_variable_set(:@view_context, view_context)

      assert_raises(NoMethodError) do
        renderer.send(:nonexistent_method)
      end
    end

    def test_respond_to_missing_returns_true_for_view_context_methods
      renderer = Renderer.new("test")
      view_context = mock("view_context")
      view_context.stubs(:respond_to?).with(:some_helper, false).returns(true)

      renderer.instance_variable_set(:@view_context, view_context)

      assert_respond_to renderer, :some_helper
    end

    def test_respond_to_missing_returns_false_for_unknown_methods
      renderer = Renderer.new("test")
      view_context = Object.new
      renderer.instance_variable_set(:@view_context, view_context)

      refute_respond_to renderer, :nonexistent_method
    end

    def test_log_error_uses_rails_logger_when_available
      renderer = Renderer.new("test")
      rails_logger = mock("logger")
      rails_logger.expects(:error).with("TypstRails: Test error")

      rails_class = Class.new
      rails_class.define_singleton_method(:logger) { rails_logger }
      rails_class.define_singleton_method(:respond_to?) { |m| m == :logger }

      with_defined_constant(:Rails, rails_class) do
        renderer.send(:log_error, "Test error")
      end
    end

    def test_log_error_uses_warn_when_rails_not_available
      renderer = Renderer.new("test")

      with_undefined_constant(:Rails) do
        assert_output(nil, "TypstRails: Test error\n") do
          renderer.send(:log_error, "Test error")
        end
      end
    end

    # MARK: - Source size boundary
    #
    # MAX_SOURCE_SIZE is a byte limit, not a character limit, so the boundary
    # cases matter for multibyte sources.

    def test_source_exactly_at_the_size_limit_is_accepted
      source = "a" * Renderer::MAX_SOURCE_SIZE

      renderer = Renderer.new(source)

      assert_equal Renderer::MAX_SOURCE_SIZE, renderer.source.bytesize
    end

    def test_source_one_byte_over_the_limit_is_rejected
      source = "a" * (Renderer::MAX_SOURCE_SIZE + 1)

      error = assert_raises(ArgumentError) { Renderer.new(source) }

      assert_includes error.message, "too large"
    end

    # A multibyte string can be under the character count but over the byte
    # limit; the check must use bytesize.
    def test_size_limit_counts_bytes_not_characters
      # "日" is 3 bytes in UTF-8.
      source = "日" * ((Renderer::MAX_SOURCE_SIZE / 3) + 1)

      assert_operator source.length, :<, Renderer::MAX_SOURCE_SIZE
      assert_raises(ArgumentError) { Renderer.new(source) }
    end

    def test_error_message_reports_both_actual_and_maximum_size
      source = "a" * (Renderer::MAX_SOURCE_SIZE + 1)

      error = assert_raises(ArgumentError) { Renderer.new(source) }

      assert_includes error.message, (Renderer::MAX_SOURCE_SIZE + 1).to_s
      assert_includes error.message, Renderer::MAX_SOURCE_SIZE.to_s
    end

    # MARK: - Source coercion

    def test_non_string_source_is_coerced_via_to_s
      renderer = Renderer.new(12_345)

      assert_equal "12345", renderer.source
    end

    def test_empty_source_is_accepted_at_construction_and_rejected_at_render
      renderer = Renderer.new("")

      assert_empty renderer.source
      error = assert_raises(ArgumentError) { renderer.render(nil, {}) }
      assert_includes error.message, "Source is empty"
    end

    def test_false_source_is_coerced_rather_than_treated_as_nil
      renderer = Renderer.new(false)

      assert_equal "false", renderer.source
    end

    # MARK: - view_context bookkeeping

    def test_view_context_is_nil_before_render
      renderer = Renderer.new("= Test")

      assert_nil renderer.view_context
    end

    def test_render_records_the_view_context
      mock_successful_typst_compilation
      view = Struct.new(:assigns).new({ title: "T" })
      renderer = Renderer.new("= Test")

      renderer.render(view, {})

      assert_same view, renderer.view_context
    end

    # MARK: - Data serialization

    def test_render_writes_symbolized_keys_to_the_json_data_file
      force_cli_backend!
      captured = nil

      Open3.stubs(:capture3).with do |*args|
        output_path = args.last
        data_path = File.join(File.dirname(output_path), "typst_data.json")
        captured = JSON.parse(File.read(data_path)) if File.exist?(data_path)
        File.binwrite(output_path, "pdf") if output_path.end_with?(".pdf")
        true
      end.returns(["", "", mock_status(true)])

      view = Struct.new(:assigns).new({ "string_key" => 1 })
      Renderer.new("= Test").render(view, { "local_key" => 2 })

      assert_equal({ "string_key" => 1, "local_key" => 2 }, captured)
    end

    def test_render_without_view_context_passes_local_assigns_through_unchanged
      force_cli_backend!
      captured = nil

      Open3.stubs(:capture3).with do |*args|
        output_path = args.last
        data_path = File.join(File.dirname(output_path), "typst_data.json")
        captured = JSON.parse(File.read(data_path)) if File.exist?(data_path)
        File.binwrite(output_path, "pdf") if output_path.end_with?(".pdf")
        true
      end.returns(["", "", mock_status(true)])

      Renderer.new("= Test").render(nil, { title: "Report", count: 3 })

      assert_equal({ "title" => "Report", "count" => 3 }, captured)
    end

    # MARK: - transform_value_for_json_serialization

    def test_transform_leaves_primitives_untouched
      renderer = Renderer.new("= Test")

      [nil, true, false, 42, 3.5, "text", :sym].each do |value|
        result = renderer.send(:transform_value_for_json_serialization, value)
        value.nil? ? assert_nil(result) : assert_equal(value, result)
      end
    end

    def test_transform_handles_an_empty_array_and_hash
      renderer = Renderer.new("= Test")

      assert_empty renderer.send(:transform_value_for_json_serialization, [])
      assert_empty renderer.send(:transform_value_for_json_serialization, {})
    end

    def test_transform_converts_dates_nested_inside_arrays_of_hashes
      renderer = Renderer.new("= Test")
      date = Date.new(2024, 3, 1)

      result = renderer.send(:transform_value_for_json_serialization, [{ due: date }])

      assert_equal [{ due: "2024-03-01" }], result
    end

    def test_transform_preserves_hash_keys_while_converting_values
      renderer = Renderer.new("= Test")

      result = renderer.send(:transform_value_for_json_serialization, { "a" => Date.new(2024, 1, 2), b: 1 })

      assert_equal({ "a" => "2024-01-02", b: 1 }, result)
    end

    # MARK: - respond_to_missing? / method_missing without a view context

    def test_respond_to_missing_is_false_when_no_view_context_is_set
      renderer = Renderer.new("= Test")

      refute_respond_to renderer, :some_helper
    end

    def test_method_missing_raises_no_method_error_when_no_view_context_is_set
      renderer = Renderer.new("= Test")

      assert_raises(NoMethodError) { renderer.some_helper }
    end

    # The renderer includes Helpers, so helper methods must resolve directly
    # rather than falling through to method_missing.
    def test_helper_methods_are_available_on_the_renderer
      renderer = Renderer.new("= Test")

      assert_respond_to renderer, :escape_typst
      assert_equal "\\$100", renderer.escape_typst("$100")
    end

    # MARK: - ActiveRecord detection
    #
    # active_record_value? checks Base and Relation separately, guarding each
    # with defined? so the gem works with no ActiveRecord loaded at all.

    def test_active_record_relations_are_serialized_via_as_json
      renderer = Renderer.new("= Test")
      active_record_module = Module.new
      active_record_module.const_set(:Base, Class.new)
      relation_class = Class.new do
        def as_json
          [{ "id" => 1 }, { "id" => 2 }]
        end
      end
      active_record_module.const_set(:Relation, relation_class)

      with_defined_constant(:ActiveRecord, active_record_module) do
        result = renderer.send(:transform_value_for_json_serialization, relation_class.new)

        assert_equal([{ "id" => 1 }, { "id" => 2 }], result)
      end
    end

    # With ActiveRecord::Base defined but no Relation constant, the check must
    # short-circuit rather than raise NameError.
    def test_missing_relation_constant_does_not_raise
      renderer = Renderer.new("= Test")
      active_record_module = Module.new
      active_record_module.const_set(:Base, Class.new)

      with_defined_constant(:ActiveRecord, active_record_module) do
        refute renderer.send(:active_record_value?, "plain string")
      end
    end

    def test_non_active_record_values_are_not_treated_as_records
      renderer = Renderer.new("= Test")
      active_record_module = Module.new
      active_record_module.const_set(:Base, Class.new)
      active_record_module.const_set(:Relation, Class.new)

      with_defined_constant(:ActiveRecord, active_record_module) do
        refute renderer.send(:active_record_value?, { plain: "hash" })
        refute renderer.send(:active_record_value?, [1, 2, 3])
      end
    end

    # The common case for this gem: no ActiveRecord in the process at all.
    def test_active_record_check_is_false_when_active_record_is_absent
      renderer = Renderer.new("= Test")

      with_undefined_constant(:ActiveRecord) do
        refute renderer.send(:active_record_value?, Object.new)
      end
    end

    # MARK: - compile_typst_source guards
    #
    # #render validates its own inputs first, so these guards are only
    # reachable by calling the private method directly. They still protect
    # any future caller inside the class.

    def test_compile_typst_source_rejects_a_nil_source
      error = assert_raises(ArgumentError) do
        Renderer.new("= Test").send(:compile_typst_source, nil, {})
      end
      assert_equal "typst_source cannot be empty", error.message
    end

    def test_compile_typst_source_rejects_an_empty_source
      assert_raises(ArgumentError) do
        Renderer.new("= Test").send(:compile_typst_source, "", {})
      end
    end

    def test_compile_typst_source_rejects_non_hash_data
      error = assert_raises(ArgumentError) do
        Renderer.new("= Test").send(:compile_typst_source, "= Test", [])
      end
      assert_equal "data must be a Hash", error.message
    end

    def test_write_typst_data_file_skips_nil_data
      paths = Renderer::TempPaths.new(Dir.tmpdir)
      File.expects(:write).never

      Renderer.new("= Test").send(:write_typst_data_file, paths, nil)

      assert_nil paths.data_file_path
    end

    # MARK: - Files handed to the compiler

    def test_render_writes_the_source_verbatim_to_the_typ_file
      force_cli_backend!
      source = "= Résumé — 日本語 ✓\n#let x = 1\n"
      written = nil

      Open3.stubs(:capture3).with do |*args|
        written = File.binread(args[-2])
        File.binwrite(args.last, "pdf")
        true
      end.returns(["", "", mock_status(true)])

      Renderer.new(source).render(nil, {})

      assert_equal source.b, written
    end

    # Templates load their data with json("typst_data.json"), a path Typst
    # resolves relative to the source file and confines to --root. All three
    # must therefore share a directory.
    def test_data_file_source_file_and_root_share_a_directory
      force_cli_backend!
      root = typ_path = nil
      data_file_present = false

      Open3.stubs(:capture3).with do |*args|
        root = args[args.index("--root") + 1]
        typ_path = args[-2]
        data_file_present = File.exist?(File.join(root, "typst_data.json"))
        File.binwrite(args.last, "pdf")
        true
      end.returns(["", "", mock_status(true)])

      Renderer.new("= Test").render(nil, { title: "x" })

      assert_equal root, File.dirname(typ_path)
      assert data_file_present, "typst_data.json should exist in the root directory at compile time"
    end

    def test_temp_source_file_has_a_typ_extension
      force_cli_backend!
      typ_path = nil

      Open3.stubs(:capture3).with do |*args|
        typ_path = args[-2]
        File.binwrite(args.last, "pdf")
        true
      end.returns(["", "", mock_status(true)])

      Renderer.new("= Test").render(nil, {})

      assert_equal ".typ", File.extname(typ_path)
    end

    # MARK: - Data merging across key types

    # Assigns arrive with string keys from Rails, locals usually with symbols.
    # Both are symbolized before merging so the same name collides and the
    # local wins, instead of both surviving as "title" and :title.
    def test_string_keyed_assign_and_symbol_keyed_local_collide
      renderer = Renderer.new("= Test")
      view = Struct.new(:assigns).new({ "title" => "from assigns" })

      data = renderer.send(:collect_data_for_typst, view, { title: "from locals" })

      assert_equal({ title: "from locals" }, data)
    end

    def test_symbol_keyed_assign_and_string_keyed_local_collide
      renderer = Renderer.new("= Test")
      view = Struct.new(:assigns).new({ title: "from assigns" })

      data = renderer.send(:collect_data_for_typst, view, { "title" => "from locals" })

      assert_equal({ title: "from locals" }, data)
    end

    def test_collect_data_does_not_mutate_local_assigns
      renderer = Renderer.new("= Test")
      view = Struct.new(:assigns).new({ "a" => 1 })
      locals = { "when" => Date.new(2024, 1, 2) }
      original = locals.dup

      renderer.send(:collect_data_for_typst, view, locals)

      assert_equal original, locals
    end

    def test_collect_data_converts_dates_held_in_assigns
      renderer = Renderer.new("= Test")
      view = Struct.new(:assigns).new({ "due" => Date.new(2024, 3, 9), "items" => [{ at: Date.new(2024, 3, 10) }] })

      data = renderer.send(:collect_data_for_typst, view, {})

      assert_equal "2024-03-09", data[:due]
      assert_equal [{ at: "2024-03-10" }], data[:items]
    end

    # Values from locals are transformed only when a view context is present;
    # without one they go straight to to_json, which ActiveSupport also
    # renders as ISO8601. Either way the template sees the same string.
    def test_dates_serialize_identically_with_and_without_a_view_context
      force_cli_backend!
      captured = []

      Open3.stubs(:capture3).with do |*args|
        captured << JSON.parse(File.read(File.join(File.dirname(args.last), "typst_data.json")))
        File.binwrite(args.last, "pdf")
        true
      end.returns(["", "", mock_status(true)])

      locals = { due: Date.new(2024, 3, 9) }
      Renderer.new("= Test").render(nil, locals)
      Renderer.new("= Test").render(Struct.new(:assigns).new({}), locals)

      assert_equal captured[0], captured[1]
      assert_equal "2024-03-09", captured[0]["due"]
    end

    # MARK: - Repeated renders

    def test_a_renderer_can_render_more_than_once
      mock_successful_typst_compilation(pdf_content: "pdf")
      renderer = Renderer.new("= Test")

      assert_equal "pdf", renderer.render(nil, { a: 1 })
      assert_equal "pdf", renderer.render(nil, { a: 2 })
    end

    def test_a_later_render_without_a_view_context_clears_the_previous_one
      mock_successful_typst_compilation
      renderer = Renderer.new("= Test")

      renderer.render(Struct.new(:assigns).new({}), {})
      renderer.render(nil, {})

      assert_nil renderer.view_context
    end

    # MARK: - Delegation details

    def test_method_missing_forwards_blocks_to_the_view_context
      view = Class.new do
        def capture_helper
          "<#{yield}>"
        end
      end.new

      renderer = Renderer.new("= Test")
      renderer.instance_variable_set(:@view_context, view)

      assert_equal "<inner>", renderer.send(:capture_helper) { "inner" }
    end

    def test_method_missing_forwards_keyword_arguments_to_the_view_context
      view = Class.new do
        def tag_helper(name, cls:)
          "#{name}.#{cls}"
        end
      end.new

      renderer = Renderer.new("= Test")
      renderer.instance_variable_set(:@view_context, view)

      assert_equal "div.box", renderer.send(:tag_helper, "div", cls: "box")
    end

    # Renderer's own methods win over the view context's.
    def test_own_helpers_are_not_delegated
      view = mock("view_context")
      view.expects(:escape_typst).never

      renderer = Renderer.new("= Test")
      renderer.instance_variable_set(:@view_context, view)

      assert_equal "\\#x", renderer.escape_typst("#x")
    end

    private

    # Runs the block with a backend that records the root directory it was
    # given, and returns that directory.
    def capture_compile_root
      root = nil
      backend = stub("backend")
      backend.stubs(:compile).with { |_typ, dir| root = dir }.returns("pdf")
      Backends::Registry.stubs(:resolve).returns(backend)
      yield
      root
    end

    def mock_view_context(assigns_hash)
      context = mock("view_context")
      context.stubs(:assigns).returns(assigns_hash)
      context.stubs(:respond_to?).with(:assigns).returns(true)
      context
    end
  end
end
