# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `config.pdf_standard` to have Typst enforce PDF standards such as PDF/UA-1
  (`:ua_1`) and PDF/A (`:a_2b` and others). Accepts a symbol or an array of
  symbols, and works with both the CLI and gem backends. PDF/UA-1 requires the
  template to set a document title.
- `config.font_paths` to add directories that Typst searches for fonts, and
  `config.ignore_system_fonts` to skip the system's fonts. Both backends pass
  them to Typst: the CLI as `--font-path` and `--ignore-system-fonts`, the
  `typst` gem as its `font_paths:` and `ignore_system_fonts:` options.
- `TypstRails::Configuration#compile_options`, the compiler options that
  backends pass through to Typst.
- `TypstRails::CompileError`, a subclass of `TypstRails::Error`, raised when
  Typst rejects a template. It carries the parsed diagnostics (severity,
  message, path, line, column, hints), the line and column of the first
  error, the template's name, the offending source line, Typst's output, and,
  for the CLI backend, the command that was run.
- `TypstRails::Renderer.new` accepts an optional `template:` name. The Rails
  handler passes the view's path, and the Sinatra and Rage helpers pass the
  template path, so errors name the template instead of a temporary file.
- `config.on_warning`, called with the warnings from a successful CLI
  compile and the template's name. By default it logs them. The `typst` gem
  does not expose warnings on success, so it is not called for the `:gem`
  backend.
- `TypstRails.render(template, locals:, assigns:, root:)` renders a `.typ`
  template file to PDF outside a request, for background jobs, mailers, and
  scripts. The template runs through ERB, then compiles, with locals and
  assigns also written to `typst_data.json`. Relative paths resolve against
  `app/views` in Rails and the current directory elsewhere, the `.typ`
  extension is optional, and paths that lead outside the root raise
  `ArgumentError`.
- `TypstRails.render_with_rails(template, locals:, assigns:, controller:)`
  renders a `.typ` view through a Rails controller, so app helpers, route
  helpers, and partials work outside a request. It raises
  `TypstRails::Error` when ActionController is not loaded.
- `TypstRails.render_and_attach(attachable, template, filename:, ...)`
  renders a template and passes the PDF to `attachable.attach`, such as an
  ActiveStorage attachment. Pass `via: :rails` to render through
  `render_with_rails`.

### Changed
- Compile error messages name the template and the location of the first
  error, and replace paths into the render's temporary directory with the
  template's name or root-relative paths. The full command line is no longer
  part of the message; it is available as `CompileError#command`.
- Warnings printed by a successful CLI compile are no longer discarded.
- **Behavior change:** a local whose value has no faithful JSON form now
  raises `TypstRails::SerializationError` (a subclass of `TypstRails::Error`)
  when the template reads `typst_data.json`. The message names the key path,
  such as `locals.line_items[0].amount is a Money, which is not
  JSON-serializable`, and says how to fix it. Such values used to reach the
  template as `{}`, a dump of the object's instance variables, or its `#to_s`,
  depending on whether ActiveSupport was loaded. Rejected values include plain
  objects without their own `as_json` or `to_h`, Procs, IO objects,
  Rationals, NaN and Infinity, strings with no valid UTF-8 form, and Hashes
  with keys other than Strings, Symbols or numbers.
- An instance variable with no faithful JSON form is left out of
  `typst_data.json`, with one warning per render (to `Rails.logger` when
  present) naming each variable and the path of the offending value. Instance
  variables whose names begin with an underscore are no longer written at all.
- Values in `typst_data.json` are converted by the new
  `TypstRails::DataSerializer`: Symbols and Hash keys become strings, Sets
  become arrays, BigDecimals become decimal strings, Structs and `Data`
  objects become objects via `to_h`, and other objects are used only when
  their class defines `as_json` or `to_h` itself. The private
  `Renderer#transform_value_for_json_serialization` now delegates to it, and
  the private `active_record_value?` check is gone: models and relations are
  handled through their own `as_json`.
- Data for templates that do not mention `typst_data.json` is no longer
  converted at all, so it cannot raise.
- The Sinatra `typst` and Rage `render_typst` helpers now share the template
  rendering code behind `TypstRails.render`. Their behavior is unchanged.

### Fixed
- `gem "typst-rails"` in a Gemfile now loads the library. Bundler.require
  requires "typst-rails", but the entry point was only `typst_rails.rb`, so
  Rails apps loaded `version.rb` and nothing else: the Railtie never ran and
  `.typ` views failed with `ActionView::MissingTemplate`. The workaround,
  `require: "typst_rails"`, is no longer needed.
- `.typ` partials rendered from a `.typ` view no longer compile to a PDF of
  their own. Only the outermost `.typ` template compiles; nested ones return
  their ERB-processed Typst source to be spliced into the parent.
- Times passed as locals to a render without a view context (as with
  `Renderer.new(source).render(nil, locals)`) are now ISO 8601 strings, as they
  already were with a view context. They were written with `Time#to_s` when
  ActiveSupport was not loaded.

## [0.2.1] - 2026-11-14

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
- Rage integration now works. It previously called an empty `Rage.configure`
  block and registered nothing. Rage has no template handlers, so
  `RageController::API` now gains `render_typst(template, locals, status:)`,
  which runs the template through ERB and responds with the PDF.
- The Sinatra `typst` helper now runs templates through ERB, with the route's
  instance variables, the `TypstRails::Helpers` methods, and the locals hash
  in scope. It previously passed the file to Typst unprocessed, so data could
  reach the template only through `typst_data.json`.
- `TypstRails::Helpers` is now available in Rails views. It was mixed only
  into `Renderer`, but `.typ` templates evaluate their ERB in the view
  context, so `escape_typst` raised `NoMethodError` there. Views keep
  ActionView's `url_encode`.
- `typst_data.json` is written only when the template source mentions it.
  Every controller instance variable, including whole ActiveRecord models,
  was previously serialized to disk on each render, whether or not the
  template read it.
- `default_root_path` now sets the Typst root. It was validated but never
  read, so templates could not load files from the application. It also
  accepts a `Pathname`; the README's `Rails.root.join(...)` example raised
  `ArgumentError`.
- `markdown_to_typst` (and so `html_to_typst` and `include_markdown`) let
  link and image URLs close the Typst string they were written into. A `"`
  in a URL broke compilation, and a crafted URL could add Typst code to the
  document. URLs are now written as escaped string literals, and link titles
  (`[x](url "title")`) are dropped instead of being pasted into the URL.
- `markdown_to_typst` passed ordinary text through as Typst syntax, so
  `#hashtag` ran as code, `$5 or $10` became math, `me@example.com` became a
  reference, and an unmatched `**` or `_` opened emphasis. Text is now escaped
  with `escape_typst`, and only the Markdown the converter recognizes becomes
  Typst markup. This changes output for text that was previously passed
  through raw: Typst markup given to `markdown_to_typst` is now escaped
  rather than kept.
- `markdown_to_typst` now honors Markdown backslash escapes (`\*`, `\#`,
  `\[`, and a trailing `# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

 as a hard line break) and converts autolinks
  (`<https://...>`).
- `markdown_to_typst` converts `*` and `+` bullets to `-`. Typst has no `*`
  bullet (the line became bold text), and its `+` makes a numbered item.
  Ordered items written `1)` become `1.`.
- Text right after a converted link or image, such as `(note)` or `.field`,
  is no longer read by Typst as part of the `#link`/`#image` call.
- `Backends::Cli#available?` searches PATH in Ruby instead of running
  `which` through a shell, so the configured executable path is never
  interpreted by a shell. It also now requires the file to be executable.
- `escape_typst` now also escapes backticks, `~`, comment openers (`//`,
  `/*`), dash shorthands (`--`, `---`, `-?`) and line-start markers (`=`, `-`,
  `+`, `/`, `1.`). Text such as `a // b` previously lost everything after the
  `//`, and a line beginning `- ` became a list item.
- `markdown_to_typst` no longer rewrites the contents of inline code or fenced
  code blocks, and no longer treats `*` or `_` with whitespace on the inner
  side as emphasis (`2 * 3 * 4` was converted to `2 _ 3 _ 4`).
- Concurrent renders no longer share `typst_data.json`. Each render now
  compiles in its own temporary directory, so threads cannot read or delete
  one another's data.
- `Renderer` now forwards keyword arguments when delegating helper calls to the
  view context. On Ruby 3, helpers taking keyword arguments raised
  `ArgumentError` when called through the renderer.
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
