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
<% data = { title: @title, author: @author } %>
#let data = json("typst_data.json")

= #data.title

Author: #data.author

Generated on <%= Time.now.strftime("%Y-%m-%d") %>
```

### Rage Integration

Rage support is automatically enabled when the Rage framework is detected. Template integration follows Rage's conventions.

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

### Configuration

```ruby
TypstRails.configure do |config|
  config.typst_executable_path = "/custom/path/to/typst"
  config.default_root_path = Rails.root.join("app", "assets", "typst")
end
```

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
    # ... return PDF bytes, or raise TypstRails::Error on failure
  end
end

TypstRails::Backends::Registry.register(:my_remote, MyRemoteBackend.new)
TypstRails.configure { |config| config.backend = :my_remote }
```

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

See [e2e-docker/README.md](e2e-docker/README.md) for detailed documentation.

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

