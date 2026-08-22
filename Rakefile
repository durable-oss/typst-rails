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

DOCKER_E2E_SCENARIOS = %w[cli-only gem-only both neither fresh-install].freeze

namespace :e2e do
  desc "Run Docker-based E2E tests (backend matrix + fresh install)"
  task :docker do
    require "open3"

    compose_dir = File.join(__dir__, "e2e-docker")
    puts "Building Docker E2E images (this can take a while the first time)..."
    build_out, build_status = Open3.capture2e("docker", "compose", "build", chdir: compose_dir)
    unless build_status.success?
      puts build_out
      abort "docker compose build failed"
    end

    results = DOCKER_E2E_SCENARIOS.to_h do |scenario|
      print "  #{scenario}... "
      $stdout.flush
      output, status = Open3.capture2e("docker", "compose", "run", "--rm", scenario, chdir: compose_dir)
      puts status.success? ? "PASS" : "FAIL"
      puts output.lines.map { |l| "    #{l}" }.join unless status.success?
      [scenario, status.success?]
    end

    Open3.capture2e("docker", "compose", "down", "--remove-orphans", chdir: compose_dir)

    puts
    puts "Docker E2E summary: #{results.count { |_, ok| ok }}/#{results.size} passed"
    abort "Docker E2E failures: #{results.reject { |_, ok| ok }.keys.join(", ")}" if results.value?(false)
  end
end

desc "Run all tests (unit + E2E)"
task test_all: %i[test e2e]

task default: %i[test rubocop]
