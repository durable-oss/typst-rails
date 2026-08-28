# frozen_string_literal: true

require_relative "lib/typst_rails/version"

Gem::Specification.new do |spec|
  spec.name        = "typst-rails"
  spec.version     = TypstRails::VERSION
  spec.authors     = ["David J. Berube"]
  spec.email       = ["commercial@durableprogramming.com"]

  spec.summary     = "Typst typesetting integration for Ruby applications"
  spec.description = <<~DESC
    TypstRails integrates the Typst typesetting system with Ruby applications.
    Provides automatic framework detection and integration for Rails, Rage, and Sinatra,
    with full standalone support. Generate high-quality PDFs from Typst templates with
    built-in helpers for text escaping, HTML/Markdown conversion, and data binding.
    Developed following the Durable Philosophy emphasizing stability, long-term
    maintainability, and pragmatic solutions.
  DESC
  spec.homepage    = "https://github.com/durable-oss/typst-rails"
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/typst-rails"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is published.
  # Ship only what installed applications need: library code, executables,
  # and top-level docs. Dev tooling (devenv, CI, rubocop bin, task notes)
  # stays in git but out of the packaged gem.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").select do |f|
      f.match(%r{\A(?:lib/|exe/)}) || %w[README.md CHANGELOG.md MIT-LICENSE].include?(f)
    end
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Runtime dependencies
  # No required dependencies - works with plain Ruby
  # Optional framework integrations will be loaded automatically if detected
  spec.add_dependency "nokogiri", "~> 1.13"
  spec.add_dependency "reverse_markdown", "~> 2.0"

  # Development dependencies
  spec.add_development_dependency "bundler", ">= 2.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "minitest-reporters", "~> 1.5"
  spec.add_development_dependency "mocha", "~> 2.0"
  spec.add_development_dependency "rake", ">= 12.0"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "rubocop-minitest", "~> 0.36"
  spec.add_development_dependency "rubocop-rake", "~> 0.6"
  spec.add_development_dependency "simplecov", "~> 0.22"
end
