# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "simplecov"
SimpleCov.start do
  add_filter "/test/"
  add_filter "/vendor/"
end

require "open3"
require "minitest/autorun"
require "minitest/reporters"
require "mocha/minitest"

Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new]

# Load the gem without any framework loaded by default
require "typst_rails/framework_detection"
require "typst_rails/renderer"
require "typst_rails"

module TestHelpers
  # Helper to create temporary Typst files for testing
  def create_temp_typst_file(content)
    file = Tempfile.new(["test_", ".typ"])
    file.write(content)
    file.close
    file
  end

  # Helper to mock Open3.capture3 for successful compilation via the CLI backend.
  # Forces backend resolution to the CLI backend so Open3 stubbing is deterministic
  # regardless of which backends (e.g. the `typst` gem) happen to be installed.
  def mock_successful_typst_compilation(pdf_content: "mock pdf content")
    force_cli_backend!

    Open3.stubs(:capture3).with do |*args|
      # Extract the output path (last argument)
      output_path = args.last
      # Write mock PDF to the output file
      File.binwrite(output_path, pdf_content) if output_path.end_with?(".pdf")
      true
    end.returns(["", "", mock_status(true)])
  end

  # Helper to mock Open3.capture3 for failed compilation via the CLI backend.
  def mock_failed_typst_compilation(stderr: "Compilation error")
    force_cli_backend!

    Open3.stubs(:capture3).returns(["", stderr, mock_status(false)])
  end

  # Forces backend resolution to always return the CLI backend, so tests that
  # stub Open3 directly aren't affected by other backends (e.g. the `typst`
  # gem) being installed and preferred by auto-detection.
  def force_cli_backend!
    TypstRails::Backends::Registry.stubs(:resolve).returns(TypstRails::Backends::Cli.new)
  end

  # Helper to create a mock process status
  def mock_status(success)
    status = mock("status")
    status.stubs(:success?).returns(success)
    status
  end

  # Helper to temporarily undefine a constant
  def with_undefined_constant(const_name)
    if Object.const_defined?(const_name)
      original_value = Object.const_get(const_name)
      Object.send(:remove_const, const_name)
      begin
        yield
      ensure
        Object.const_set(const_name, original_value)
      end
    else
      yield
    end
  end

  # Helper to temporarily define a constant
  def with_defined_constant(const_name, value)
    already_defined = Object.const_defined?(const_name)
    original_value = Object.const_get(const_name) if already_defined

    Object.send(:remove_const, const_name) if already_defined
    Object.const_set(const_name, value)

    begin
      yield
    ensure
      Object.send(:remove_const, const_name)
      Object.const_set(const_name, original_value) if already_defined
    end
  end
end

module Minitest
  class Test
    include TestHelpers
  end
end
