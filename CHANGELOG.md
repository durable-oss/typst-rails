# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive YARD documentation for all public APIs
- Enhanced gemspec metadata with bug tracker and documentation URIs
- MFA requirement for RubyGems publishing
- CHANGELOG.md following Keep a Changelog format
- SECURITY.md with security reporting process

### Changed
- Improved module and class documentation with examples
- Enhanced gemspec description with clearer value proposition
- Updated author email to commercial@durableprogramming.com

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
