# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Swappable Typst compilation backends: a `:cli` backend (shells out to the
  Typst executable, the original behavior) and a `:gem` backend (uses the
  `typst` RubyGem to compile in-process when installed), selected
  automatically via `TypstRails::Backends::Registry` or set explicitly with
  `TypstRails.configure { |c| c.backend = :gem }`. Custom backends can be
  registered for other compilation strategies.
- Docker-based end-to-end tests (`e2e-tests/docker/`, `rake e2e:docker`) covering
  the backend auto-detection matrix (CLI-only, gem-only, both, neither) and a
  fresh `gem build` + `gem install` smoke test, independent of the local dev
  environment.
- Comprehensive YARD documentation for all public APIs
- Enhanced gemspec metadata with bug tracker and documentation URIs
- MFA requirement for RubyGems publishing
- CHANGELOG.md following Keep a Changelog format
- SECURITY.md with security reporting process

### Changed
- Improved module and class documentation with examples
- Enhanced gemspec description with clearer value proposition
- Updated author email to commercial@durableprogramming.com

### Removed
- **Breaking:** the `sanitize_html` helper, along with the
  `DEFAULT_ALLOWED_TAGS` and `DEFAULT_ALLOWED_ATTRIBUTES` constants. Nothing in
  the gem called it: `html_to_typst` never sanitized its input, so this was an
  opt-in helper that duplicated, less thoroughly, what dedicated sanitizers
  already do. Callers who need it should use ActionView's `sanitize` helper,
  the Rails::HTML sanitizers, Loofah, or the `sanitize` gem. Note that HTML
  sanitization was never sufficient here in any case: it strips dangerous HTML,
  but the surviving text still reaches a Typst document where `#`, `$`, `[`,
  and `@` are syntactically meaningful. See SECURITY.md.

### Fixed
- `Backends::Cli#available?` raised `NoMethodError` when the gem was loaded
  via a bare `require "typst_rails/renderer"`, because `executable_path` read
  `TypstRails.configuration` without checking that the top-level module was
  loaded. Safe navigation did not help: the method itself was undefined. The
  fault was masked wherever the `typst` gem is installed, since the `:gem`
  backend is selected first and `Cli#available?` is never reached.
- `TypstRails.configuration.typst_executable_path` is now actually used by
  the CLI backend when compiling (previously ignored, so the setting had no
  effect).

## [0.1.0] - 2024-01-XX (Initial Release)

### Added
- Core Typst rendering functionality via `TypstRails::Renderer`
- Automatic framework detection for Rails, Rage, and Sinatra
- Rails integration with `.typ` template handler
- Sinatra helper methods for Typst rendering
- Rage framework integration
- Standalone Ruby support (no framework required)
- Helper methods for text escaping, HTML/Markdown conversion, and URL encoding
- Comprehensive test suite with unit and E2E tests
- Code coverage reporting with SimpleCov
- RuboCop configuration for code quality
- Support for ERB preprocessing in Typst templates
- Automatic data binding from Rails view contexts
- JSON-based data passing to Typst templates
- Error handling with detailed error messages
- Temporary file management with automatic cleanup

### Security
- Input validation for template source size (10MB limit)
- Safe handling of temporary files with proper cleanup
- Argument validation for all public methods

[Unreleased]: https://github.com/durable-oss/typst-rails/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/durable-oss/typst-rails/releases/tag/v0.1.0
