# Typst Rails

`TypstRails` integrates the powerful [Typst](https://typst.app/) typesetting system with Ruby applications. Generate high-quality PDFs from Typst templates with seamless framework integration for Rails, Rage, and Sinatra—or use it standalone in any Ruby project.

This gem is built with [The Durable Philosophy](#the-durable-philosophy) at its core, emphasizing stability, long-term maintainability, and pragmatic solutions for real-world problems.

## Features

- **Framework-Agnostic**: Works standalone or auto-integrates with Rails, Rage, and Sinatra
- **Swappable Compilation Backends**: Prefers the `typst` gem when installed; falls back to shelling out to the Typst CLI
- **Automatic Detection**: Zero configuration needed—just install and use
- **Rails Template Handler**: Render `.typ` files like ERB templates
- **Helper Methods**: Text escaping, HTML/Markdown conversion, URL encoding
- **Data Binding**: Seamless variable passing from Ruby to Typst
- **Comprehensive Testing**: Unit and E2E tests ensure reliability
- **Well Documented**: YARD documentation for all public APIs
- **Security Conscious**: Input validation, safe file handling, and clear security guidelines

## The Durable Philosophy

This gem is developed following the Durable Programming philosophy, which emphasizes:

*   **Solving Real Problems:** Software should provide tangible value and address genuine user needs, with a customer-centric approach.
*   **Long-Term Sustainability:** Prioritizing maintainability, stability, and the ability for software to evolve gracefully over time, fostering lasting solutions.
*   **Quality and Reliability:** A strong focus on robust, well-tested code, and secure, stable systems, ensuring high-quality work.
*   **Pragmatism and Simplicity:** Favoring proven, effective solutions and clear, modular design over unnecessary complexity or chasing trends.
*   **Transparency and Honesty:** Open communication, realistic expectations, and comprehensive, accessible documentation.
*   **Developer Experience:** Creating tools and processes that are efficient, enjoyable, and enhance productivity.
*   **Ethical Practices:** A commitment to fair collaboration, respect for intellectual property, and giving back to the developer community.
*   **Continuous Improvement:** Iteratively refining software and processes based on feedback, learning, and evolving best practices.

This philosophy guides all aspects of the gem's development, from initial design to ongoing support and upgrades.

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

## Usage

`TypstRails` works standalone with plain Ruby or automatically integrates with your web framework (Rails, Rage, or Sinatra) when detected.

### Standalone Usage (Plain Ruby)

```ruby
require 'typst_rails'

# Create a Typst template
typst_source = <<~TYPST
  #let data = json("typst_data.json")
  = #data.title

  Author: #data.author

  This is a document generated with Typst!
TYPST

# Render to PDF
renderer = TypstRails::Renderer.new(typst_source)
pdf_data = renderer.render(nil, {
  title: "Monthly Report",
  author: "Durable Systems Inc."
})

# Save or send the PDF
File.binwrite("output.pdf", pdf_data)
```

### Rails Integration

When Rails is detected, `.typ` templates are automatically registered and work just like ERB templates:

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

### Helpers

The gem provides several helper methods for working with Typst templates:

#### Text Escaping

```ruby
escape_typst("Price: $100")  # => "Price: \\$100"
escape_typst("Hello #world") # => "Hello \\#world"
```

#### HTML to Markdown/Typst Conversion

```ruby
# Convert HTML to Markdown
html_to_markdown("<h1>Title</h1><p>Content</p>")
# => "# Title\n\nContent"

# Convert HTML directly to Typst
html_to_typst("<h1>Title</h1>")
# => "= Title\n\n"

# Sanitize HTML before conversion
sanitize_html('<script>alert("xss")</script><p>Safe</p>')
# => "<p>Safe</p>"
```

#### Markdown Conversion

```ruby
# Convert Markdown to Typst syntax
markdown_to_typst("# Title\n## Subtitle")
# => "= Title\n== Subtitle"

# Include external Markdown files
include_markdown("./content.md")
# Reads and converts the file to Typst syntax
```

#### URL Encoding

```ruby
url_encode("hello world") # => "hello+world"
```

These helpers are available in:
- ERB templates (Rails) - use directly: `<%= escape_typst(@text) %>`
- Plain Ruby code - include `TypstRails::Helpers` module
- The renderer includes these helpers automatically

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

### Code Quality

Run RuboCop:

```bash
bundle exec rake rubocop
```

Run all checks (default):

```bash
bundle exec rake
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests (note: currently, the gem has a basic structure and tests will be expanded with functionality). You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Framework Support

This gem automatically detects and integrates with:

*   **Rails** - Full ActionView template handler support for `.typ` files
*   **Rage** - Integration with Rage's template system
*   **Sinatra** - Helper method for rendering Typst templates
*   **Plain Ruby** - Works standalone without any framework

No configuration needed - just require the gem and it will integrate with whatever framework is present.

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/durable-oss/typst-rails](https://github.com/durable-oss/typst-rails). This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](https://www.contributor-covenant.org) code of conduct.

Please see [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines on:
- Development setup and workflow
- Code style and testing requirements
- Pull request process
- How to report bugs and request features

Contributions should align with [The Durable Philosophy](#the-durable-philosophy), emphasizing:
*   Clear, well-documented code with YARD comments
*   Thorough testing for new features and bug fixes
*   Incremental improvements that enhance stability and usability
*   Consideration for long-term maintainability

We appreciate your interest in making `TypstRails` a better tool for everyone.

## Support and Community

- **Documentation**: [API Documentation](https://rubydoc.info/gems/typst-rails)
- **Issues**: [GitHub Issues](https://github.com/durable-oss/typst-rails/issues)
- **Security**: See [SECURITY.md](SECURITY.md) for reporting vulnerabilities
- **Email**: commercial@durableprogramming.com

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the `TypstRails` project's codebases, issue trackers, chat rooms, and mailing lists is expected to follow the [Contributor Covenant](https://www.contributor-covenant.org).
