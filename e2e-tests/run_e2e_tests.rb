#!/usr/bin/env ruby
# frozen_string_literal: true

# End-to-End Test Runner for Typst Rails
# This script tests real Typst compilation with ERB templates using all helpers

require "bundler/setup"
require "erb"
require "fileutils"
require "pathname"

# Add lib to load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "typst_rails/renderer"
require "typst_rails/helpers"

class E2ETestRunner
  include TypstRails::Helpers

  attr_reader :templates_dir, :output_dir, :results

  def initialize
    @base_dir = Pathname.new(__dir__)
    @templates_dir = @base_dir.join("templates")
    @output_dir = @base_dir.join("output")
    @results = []

    setup_output_directory
  end

  def run_all_tests # rubocop:disable Naming/PredicateMethod -- runs a suite with side effects; return value reports success
    puts "=" * 80
    puts "Running End-to-End Tests for Typst Rails"
    puts "=" * 80
    puts

    template_files = Dir.glob(@templates_dir.join("*.typ.erb")).sort

    if template_files.empty?
      puts "❌ No template files found in #{@templates_dir}"
      return false
    end

    template_files.each do |template_file|
      test_name = File.basename(template_file, ".typ.erb")
      run_test(test_name, template_file)
    end

    print_summary
    all_passed?
  end

  private

  def setup_output_directory
    FileUtils.mkdir_p(@output_dir)
    puts "Output directory: #{@output_dir}"
    puts
  end

  def run_test(test_name, template_file)
    puts "-" * 80
    puts "Test: #{test_name}"
    puts "-" * 80

    begin
      typst_source = write_typst_source(test_name, template_file)
      write_and_validate_pdf(test_name, typst_source)

      record_result(test_name, :passed, "Test completed successfully")
      puts "✅ #{test_name} PASSED"
    rescue Errno::ENOENT
      error_message = "Typst executable not found. Please install Typst: https://github.com/typst/typst"
      record_result(test_name, :skipped, error_message)
      puts "⚠️  #{test_name} SKIPPED: #{error_message}"
    rescue TypstRails::Error => e
      record_result(test_name, :failed, e.message)
      puts "❌ #{test_name} FAILED"
      puts "   Error: #{e.message}"
    rescue StandardError => e
      record_result(test_name, :failed, "#{e.class}: #{e.message}")
      puts "❌ #{test_name} FAILED"
      puts "   Error: #{e.class} - #{e.message}"
      puts "   Backtrace:"
      puts(e.backtrace.first(5).map { |line| "     #{line}" })
    end

    puts
  end

  def write_typst_source(test_name, template_file)
    erb_content = File.read(template_file)
    processed_typst = process_erb(erb_content, template_file)

    typst_file = @output_dir.join("#{test_name}.typ")
    File.write(typst_file, processed_typst)
    puts "✓ ERB processed successfully"
    puts "  Typst source: #{typst_file}"

    processed_typst
  end

  def write_and_validate_pdf(test_name, typst_source)
    renderer = TypstRails::Renderer.new(typst_source)
    pdf_data = renderer.render(nil, {})

    pdf_file = @output_dir.join("#{test_name}.pdf")
    File.binwrite(pdf_file, pdf_data)

    file_size = File.size(pdf_file)
    puts "✓ PDF generated successfully"
    puts "  PDF output: #{pdf_file}"
    puts "  File size: #{file_size} bytes"

    raise "PDF file is suspiciously small (#{file_size} bytes)" if file_size < 100

    magic = File.binread(pdf_file, 4)
    raise "Invalid PDF file (missing %PDF header)" unless magic == "%PDF"

    puts "✓ PDF validation passed"
  end

  def process_erb(erb_content, template_path)
    erb = ERB.new(erb_content, trim_mode: "-")

    # Expose __dir__ to the template as a local variable without eval.
    binding_with_dir = binding
    binding_with_dir.local_variable_set(:__dir__, File.dirname(template_path))

    erb.result(binding_with_dir)
  rescue StandardError => e
    raise TypstRails::Error, "ERB processing failed: #{e.message}"
  end

  def record_result(test_name, status, message)
    @results << {
      name: test_name,
      status: status,
      message: message
    }
  end

  def print_summary
    puts "=" * 80
    puts "Test Summary"
    puts "=" * 80

    print_summary_counts
    print_results_for_status(:failed, "Failed tests:")
    print_results_for_status(:skipped, "Skipped tests:")
  end

  def print_summary_counts
    passed = @results.count { |r| r[:status] == :passed }
    failed = @results.count { |r| r[:status] == :failed }
    skipped = @results.count { |r| r[:status] == :skipped }

    puts
    puts "Total:   #{@results.length}"
    puts "Passed:  #{passed} ✅"
    puts "Failed:  #{failed} ❌"
    puts "Skipped: #{skipped} ⚠️"
    puts
  end

  def print_results_for_status(status, heading)
    matching = @results.select { |r| r[:status] == status }
    return if matching.empty?

    puts heading
    matching.each { |result| puts "  - #{result[:name]}: #{result[:message]}" }
    puts
  end

  def all_passed?
    @results.all? { |r| %i[passed skipped].include?(r[:status]) }
  end
end

# Run tests if this file is executed directly
if __FILE__ == $PROGRAM_NAME
  runner = E2ETestRunner.new
  success = runner.run_all_tests

  exit(success ? 0 : 1)
end
