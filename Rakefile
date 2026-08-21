# frozen_string_literal: true

require "bundler/setup"
require "bundler/gem_tasks"
require "rake/testtask"
require "rubocop/rake_task"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.verbose = true
  t.warning = false
end

RuboCop::RakeTask.new

desc "Run end-to-end tests with real Typst compilation"
task :e2e do
  ruby "e2e-tests/run_e2e_tests.rb"
end

desc "Clean up generated test outputs"
task :clean_e2e do
  require "fileutils"
  output_dir = File.join(__dir__, "e2e-tests", "output")
  if File.directory?(output_dir)
    FileUtils.rm_rf(Dir.glob(File.join(output_dir, "*")))
    puts "Cleaned E2E output directory: #{output_dir}"
  end
end

desc "Run all tests (unit + E2E)"
task test_all: %i[test e2e]

task default: %i[test rubocop]
