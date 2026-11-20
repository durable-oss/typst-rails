# Typst Rails

[![CI](https://github.com/durable-oss/typst-rails/actions/workflows/ci.yml/badge.svg)](https://github.com/durable-oss/typst-rails/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/typst-rails.svg)](https://rubygems.org/gems/typst-rails)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](MIT-LICENSE)

`TypstRails` provides helpers for using [Typst](https://typst.app/) typesetting system with Ruby applications. Generate high-quality PDFs from Typst templates with seamless framework integration for Rails, Rage, and Sinatra. TypstRails can be used with either the typst gem or with a typst CLI.


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'typst-rails'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install typst-rails
```

# Rails Usage

`.typ` templates are automatically registered and work just like ERB templates:

```ruby
# app/controllers/reports_controller.rb
class ReportsController < ApplicationController
  def monthly
    @title = "Monthly Report"
    @author = "Durable Systems Inc."

    respond_to do |format|
      format.pdf { render template: "reports/monthly" }
    end
  end
end
```

```typst
<%# app/views/reports/monthly.typ %>
#let data = json("typst_data.json")

= #data.title

Author: #data.author

Generated on <%= Time.now.strftime("%Y-%m-%d") %>
```

Data reaches the template two ways. ERB runs first, in the view context, so
instance variables and helpers work as in any view; note that `<%= %>` output
is not escaped. The controller's instance variables and locals are also
serialized to `typst_data.json`, which Typst reads with `json()`. That file is
written only when the template source mentions `typst_data.json`.

The `TypstRails::Helpers` methods, such as `escape_typst` and
`markdown_to_typst`, are available in views:

```typst
= <%= escape_typst(@title) %>
```

In views, `url_encode` remains ActionView's own, which encodes spaces as `%20`.

`.typ` partials work like any other partial. Only the outermost `.typ`
template is compiled; a partial returns its Typst source, which is spliced
into the parent before the whole document compiles once:

```typst
<%# app/views/reports/monthly.pdf.typ %>
= Monthly Report

<%= render partial: "shared/footer" %>  <%# app/views/shared/_footer.pdf.typ %>
```

### Rage Integration

Rage controllers have no template handlers, so when Rage is detected,
`RageController::API` gains a `render_typst` helper instead:

```ruby
class ReportsController < RageController::API
  def monthly
    @title = "Monthly Report"
    render_typst "app/views/reports/monthly.typ", { author: "Durable Systems Inc." }
  end
end
```

As with Sinatra, the template runs through ERB in the controller's scope,
with the locals hash as local variables, and the locals are also written to
`typst_data.json`. Pass `status:` to set the response status. If
`typst-rails` loads before Rage's controllers, add
`include TypstRails::RageIntegration::ControllerHelpers` to your base
controller.

### Sinatra Integration

When Sinatra is detected, a `typst` helper method is available:

```ruby
require 'sinatra'
require 'typst_rails'

get '/report.pdf' do
  typst 'templates/report.typ', {
    title: "Monthly Report",
    author: "Durable Systems Inc."
  }
end
```

The template runs through ERB first, in the route's scope, so instance
variables, helpers such as `escape_typst`, and the locals hash are all
available. The locals are also written to `typst_data.json` for templates
that read it.

### Configuration

```ruby
TypstRails.configure do |config|
  config.typst_executable_path = "/custom/path/to/typst"
  config.default_root_path = Rails.root.join("app", "assets", "typst")
end
```

`default_root_path` sets the Typst root, so templates can load files beneath
it with root-relative paths, such as `#image("/images/logo.png")`. Each render
creates a short-lived working directory inside the root, so it must be
writable. Without it, each render compiles in a private temporary directory
and cannot read your application's files.

#### Fonts

Typst finds fonts in three places: the fonts installed on the system, the
fonts embedded in Typst itself (Libertinus Serif, New Computer Modern and
DejaVu Sans Mono), and any extra directories you name.

```ruby
TypstRails.configure do |config|
  config.font_paths = [Rails.root.join("app", "assets", "fonts")]
  config.ignore_system_fonts = true
end
```

- `font_paths` lists directories that Typst searches, recursively, for font
  files. It defaults to `[]`. A single path is accepted and wrapped in an
  Array. Relative paths are expanded against the process working directory.
- `ignore_system_fonts` stops Typst from searching the system's fonts, so
  only `font_paths` and Typst's embedded fonts are used. It defaults to
  `false`.

Both settings apply to the `:cli` backend (as `--font-path` and
`--ignore-system-fonts`) and the `:gem` backend (as the `font_paths:` and
`ignore_system_fonts:` options of `Typst::Pdf.new`).

#### Fonts in production and Docker

A slim production image usually has few fonts installed, and often not the
ones a template was designed with. Typst does not fail when a font is
missing: it warns and falls back to another font, so the PDF renders but
looks different from the one you saw in development.

To get the same output everywhere, keep the font files with the
application and point `font_paths` at them:

1. Copy the `.ttf` or `.otf` files your templates use into the app, for
   example `app/assets/fonts/`, and commit them. Check that each font's
   license allows you to redistribute it.
2. Set `config.font_paths` to that directory.
3. Optionally set `config.ignore_system_fonts = true`. Typst then skips
   scanning the system's font directories on each compile, and a document
   can no longer pick up a font that happens to be installed on one machine
   but not another. A font your templates name that is missing from
   `font_paths` then falls back in development too, so you see the problem
   before you deploy.

Nothing extra needs to be installed in the Docker image for this, since the
fonts ship inside the application directory.

#### Accessible and archival PDFs

Set `pdf_standard` to have Typst enforce a PDF standard. Use `:ua_1` for
PDF/UA-1, the accessibility standard:

```ruby
TypstRails.configure do |config|
  config.pdf_standard = :ua_1
end
```

PDF/UA-1 requires a document title. Set it in each template, or the render
raises `TypstRails::Error`:

```typst
#set document(title: "Quarterly Report")
```

Pass an array to combine standards, such as `[:a_2b, :ua_1]` for a document
that is both archival and accessible. The accepted keys are `:pdf_1_4`,
`:pdf_1_5`, `:pdf_1_6`, `:pdf_1_7`, `:pdf_2_0`, `:a_1a`, `:a_1b`, `:a_2a`,
`:a_2b`, `:a_2u`, `:a_3a`, `:a_3b`, `:a_3u`, `:a_4`, `:a_4e`, `:a_4f` and
`:ua_1`, matching the values listed by `typst compile --help`. The default,
`nil`, produces a plain PDF. Both the CLI and gem backends honor this setting.

### Compilation Backends

`TypstRails` compiles documents through a pluggable backend. Two backends ship
with the gem:

- **`:cli`** shells out to the `typst` executable. This is the original
  approach and requires Typst to be [installed separately](https://typst.app/docs/tutorial/setup/)
  and available on `PATH`.
- **`:gem`** uses the [`typst`](https://rubygems.org/gems/typst) RubyGem, a
  native extension that compiles in-process—no subprocess or separate Typst
  install required. Add it to your Gemfile to enable it:

  ```ruby
  gem "typst"
  ```

By default (`config.backend = :auto`), TypstRails prefers the `typst` gem
when it's installed and falls back to the CLI otherwise. Force a specific
backend if you need to:

```ruby
TypstRails.configure do |config|
  config.backend = :gem # or :cli
end
```

You can also register your own backend—for example, to compile against a
remote Typst service:

```ruby
class MyRemoteBackend < TypstRails::Backends::Base
  def available?
    true
  end

  def compile(typ_path, root_dir)
    # ... return PDF bytes. If Typst rejects the source, raise
    # TypstRails::CompileError with Typst's diagnostic output as the message;
    # raise TypstRails::Error for other failures. To report warnings from a
    # successful compile, yield Typst's diagnostic output to the block.
  end
end

TypstRails::Backends::Registry.register(:my_remote, MyRemoteBackend.new)
TypstRails.configure { |config| config.backend = :my_remote }
```

### Errors

When Typst rejects a template, rendering raises `TypstRails::CompileError`, a
subclass of `TypstRails::Error`, so existing `rescue TypstRails::Error` code
keeps working. The message names the template and the location of the first
error, followed by Typst's own report:

```
Typst compilation failed in app/views/reports/show.pdf.typ:4:9: unknown variable: foo
(Line numbers count lines of the compiled Typst source, after any ERB evaluation.)

error: unknown variable: foo
  ┌─ app/views/reports/show.pdf.typ:4:9
  │
4 │ #let x = foo(1)
  │          ^^^
```

Each render compiles a copy of the template in a temporary directory. Paths
into that directory are replaced in the message: the template becomes its
name (the view path in Rails, the path you passed to the Sinatra and Rage
helpers, or `(inline source)` for a `Renderer` built from a string), other
files under the Typst root become root-relative paths such as `/lib.typ`, and
files next to the template, such as `typst_data.json`, are shown by name.
To name a template yourself, pass `template:` to `TypstRails::Renderer.new`:

```ruby
TypstRails::Renderer.new(File.read(path), template: path).render(nil, data)
```

The error also carries the details as attributes:

```ruby
rescue TypstRails::CompileError => e
  e.template      # => "app/views/reports/show.pdf.typ", or nil
  e.line          # => 4, line of the first error
  e.column        # => 9, column of the first error
  e.source_line   # => "#let x = foo(1)", when the error is in the template
  e.diagnostics   # => every error and warning, with severity, message,
                  #    path, line, column and hints
  e.errors        # => just the errors
  e.warnings      # => just the warnings
  e.typst_message # => Typst's output, with paths rewritten
  e.command       # => the command line the CLI backend ran, for debugging
end
```

Line numbers refer to the source Typst compiled. For `.typ` views and the
Sinatra and Rage helpers, that is the template after ERB evaluation, so an
ERB tag that expands to several lines, or a `<% %>` line that is trimmed
away, shifts them relative to the file on disk; `source_line` shows the line
Typst actually saw. Columns are counted from 0, as Typst prints them.

Parsing is best-effort. If Typst's output is not in a format TypstRails
recognizes, you still get a `CompileError` with the raw output in the message
and in `typst_message`, and `diagnostics` is empty.

### Warnings

Typst can report warnings, such as an unknown font family, on a compile that
succeeds. With the CLI backend, TypstRails passes them to `config.on_warning`,
which is called with an array of diagnostics and the template's name (or
nil). By default the warnings are logged with `Rails.logger.warn`, or with
`Kernel#warn` outside Rails:

```ruby
TypstRails.configure do |config|
  # Fail tests on any Typst warning:
  config.on_warning = ->(warnings, template) do
    raise "Typst warnings in #{template}: #{warnings.map(&:to_s).join(", ")}"
  end

  # Or ignore them:
  # config.on_warning = nil
end
```

An error raised by the handler propagates from the render.

The `typst` gem returns only the PDF on a successful compile, so with the
`:gem` backend `on_warning` is never called. Warnings that accompany a failed
compile are included in `CompileError#warnings` with either backend.

## Testing

The gem includes comprehensive testing at multiple levels:

### Unit Tests

Run the unit test suite:

```bash
bundle exec rake test
```

Tests cover:
- Framework detection (Rails, Rage, Sinatra)
- Core renderer functionality
- Error handling and edge cases
- All helper methods
- Input validation and defensive programming

### End-to-End Tests

**Requires Typst to be installed.**

The E2E tests process real ERB templates using all helpers and compile them with Typst to generate actual PDFs:

```bash
# Run E2E tests
bundle exec rake e2e

# Run all tests (unit + E2E)
bundle exec rake test_all

# Clean up generated test outputs
bundle exec rake clean_e2e
```

E2E tests verify:
- Text escaping with real Typst special characters
- HTML to Typst conversion with actual compilation
- Markdown to Typst syntax transformation
- External Markdown file inclusion
- Complex real-world templates with multiple helpers

See [e2e-tests/README.md](e2e-tests/README.md) for detailed documentation.

### Docker End-to-End Tests

**Requires Docker.**

Verifies backend auto-detection (`:cli` vs `:gem`) across isolated container
environments, and that the gem works correctly when built and installed like
a real release rather than loaded from the working tree:

```bash
bundle exec rake e2e:docker
```

See [e2e-tests/docker/README.md](e2e-tests/docker/README.md) for detailed documentation.

### Code Coverage

```bash
bundle exec rake test
# Coverage report will be in coverage/index.html
open coverage/index.html
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests (note: currently, the gem has a basic structure and tests will be expanded with functionality). You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/durable-oss/typst-rails](https://github.com/durable-oss/typst-rails). This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](https://www.contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

