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
- `markdown_to_typst` mangled combined bold+italic: `***text***` came out as
  `*_text*_` with mismatched markers, because the bold pass matched only two
  of the three asterisks and stranded the third inside the text. `***text***`
  and `___text___` are now recognized as a single token and convert to
  `*_text_*`.
- `markdown_to_typst` rewrote `\x01` and `\x02` in the caller's own text to
  `*`. Those bytes were used as internal placeholders while converting
  emphasis, so any already present in the input were indistinguishable from
  markers the conversion had written. Placeholders moved to the Unicode
  private use area, and any that do appear in the source are now held aside
  and restored verbatim.
- `FrameworkDetection.rails?`, `.rage?`, and `.sinatra?` returned `nil` rather
  than `false` when the framework was absent, because `defined?` yields a
  String or nil and the expressions were not coerced. They now return real
  booleans, so callers comparing against `false` or serializing the result
  behave as expected.
- `Backends::Cli#available?` raised `NoMethodError` when the gem was loaded
  via a bare `require "typst_rails/renderer"`, because `executable_path` read
  `TypstRails.configuration` without checking that the top-level module was
  loaded. Safe navigation did not help: the method itself was undefined. The
  fault was masked wherever the `typst` gem is installed, since the `:gem`
  backend is selected first and `Cli#available?` is never reached.
- `TypstRails.configuration.typst_executable_path` is now actually used by
  the CLI backend when compiling (previously ignored, so the setting had no
  effect).
- Three E2E templates failed to compile because they fed Typst syntax it
  could not parse. `02_html_conversion` piped `html_to_markdown` output --
  raw Markdown, where `#` starts a heading -- directly into the document,
  which Typst reads as code; it is now shown verbatim in a `#raw()` block.
  `03_markdown_conversion` referenced a remote image, which Typst refuses to
  fetch; the image case is now asserted as generated markup instead, since the
  renderer compiles from a temp dir whose `--root` cannot reach repo files.
  `05_complex_template` passed plain text containing `#` and `*` through
  `html_to_typst`, which does not escape Typst metacharacters; the fixtures
  are now the HTML that helper expects.

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
