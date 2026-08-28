# Contributing to Durable Typst

Thank you for your interest in contributing to `typst-rails`! This document provides guidelines and instructions for contributing to the project.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Development Workflow](#development-workflow)
- [Code Standards](#code-standards)
- [Testing Requirements](#testing-requirements)
- [Documentation](#documentation)
- [Pull Request Process](#pull-request-process)
- [Reporting Issues](#reporting-issues)
- [Releasing](#releasing)
- [Code of Conduct](#code-of-conduct)

## Getting Started

Before contributing, please:

1. Read the [README.md](README.md) to understand the project
2. Review the [Durable Philosophy](README.md#the-durable-philosophy)
3. Check [existing issues](https://github.com/durable-oss/typst-rails/issues) to avoid duplicates
4. Read this entire contributing guide

## Development Setup

### Prerequisites

- Ruby 2.7 or higher
- Bundler 2.0 or higher
- Git
- Typst CLI (for E2E tests)

### Installation

1. Fork and clone the repository:
   ```bash
   git clone https://github.com/YOUR-USERNAME/typst-rails.git
   cd typst-rails
   ```

2. Install dependencies:
   ```bash
   bundle install
   ```

3. Install Typst (for E2E tests):
   ```bash
   # macOS
   brew install typst

   # Linux
   # See https://github.com/typst/typst#installation

   # Windows
   # See https://github.com/typst/typst#installation
   ```

4. Run the test suite to verify setup:
   ```bash
   bundle exec rake test
   ```

## Development Workflow

### Making Changes

1. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following our [code standards](#code-standards)

3. Add tests for new functionality

4. Update documentation as needed

5. Run the full test suite:
   ```bash
   bundle exec rake test_all
   ```

6. Run RuboCop to check code style:
   ```bash
   bundle exec rubocop
   ```

7. Commit your changes with clear, descriptive messages:
   ```bash
   git add .
   git commit -m "Add feature: your feature description"
   ```

### Commit Message Guidelines

- Use present tense ("Add feature" not "Added feature")
- Use imperative mood ("Move cursor to..." not "Moves cursor to...")
- Limit the first line to 72 characters or less
- Reference issues and pull requests when relevant
- Include "Breaking:" prefix for breaking changes

**Examples:**
```
Add HTML sanitization to html_to_typst helper

Fix renderer cleanup when compilation fails

Breaking: Change configuration API to use blocks
```

## Code Standards

### Ruby Style Guide

- Follow the [Ruby Style Guide](https://rubystyle.guide/)
- Use RuboCop for style enforcement
- Run `bundle exec rubocop` before committing
- Configuration: [.rubocop.yml](.rubocop.yml)

### Code Organization

- **Single Responsibility**: Each class/module has one clear purpose
- **Composition over Inheritance**: Prefer modules and composition
- **Explicit over Implicit**: Clear method names and interfaces
- **Fail Fast**: Validate inputs and raise errors early

### Naming Conventions

- **Classes/Modules**: PascalCase (`TypstRenderer`, `FrameworkDetection`)
- **Methods**: snake_case (`render_template`, `to_typst`)
- **Constants**: SCREAMING_SNAKE_CASE (`MAX_SOURCE_SIZE`)
- **Files**: snake_case matching class names

## Testing Requirements

### Test Coverage

- All new features must include tests
- Maintain >90% code coverage
- Tests must pass on all supported Ruby versions
- Use Minitest for consistency with existing tests

### Test Types

#### Unit Tests

Located in `test/durable/typst/`:

```ruby
class RendererTest < Minitest::Test
  def test_render_with_valid_source
    # Test implementation
  end

  def test_render_with_invalid_source
    # Test error handling
  end
end
```

#### E2E Tests

Located in `e2e-tests/`:

- Test real Typst compilation
- Verify PDF generation
- Test all helper methods in practice

#### Running Tests

```bash
# Unit tests only
bundle exec rake test

# E2E tests only (requires Typst)
bundle exec rake e2e

# All tests
bundle exec rake test_all

# With coverage
bundle exec rake test
open coverage/index.html
```

### Test Best Practices

- **Descriptive Names**: `test_render_escapes_special_characters`
- **Arrange-Act-Assert**: Structure tests clearly
- **One Assertion per Test**: Focus each test
- **Test Edge Cases**: Empty inputs, nil values, large inputs
- **Mock External Dependencies**: Use Mocha for mocking

## Documentation

### YARD Documentation

All public methods must have YARD documentation:

```ruby
# Renders a Typst template to PDF
#
# @param view_context [Object, nil] Optional view context with helpers and instance variables
# @param local_assigns [Hash] Local variables to pass to the template
# @return [String] Binary PDF data
# @raise [ArgumentError] if local_assigns is not a Hash
# @raise [TypstRails::Error] if compilation fails
#
# @example Render with data
#   renderer = Renderer.new(source)
#   pdf = renderer.render(nil, { title: "Report" })
def render(view_context = nil, local_assigns = {})
  # Implementation
end
```

### Documentation Requirements

- Document all public methods with YARD comments
- Include parameter types and descriptions
- Document return values and exceptions
- Provide usage examples
- Update README.md for user-facing changes
- Update CHANGELOG.md with your changes

## Pull Request Process

### Before Submitting

Ensure your PR meets these requirements:

- [ ] All tests pass (`bundle exec rake test_all`)
- [ ] RuboCop passes (`bundle exec rubocop`)
- [ ] Code coverage is maintained (>90%)
- [ ] YARD documentation is complete
- [ ] CHANGELOG.md is updated
- [ ] README.md is updated (if applicable)
- [ ] Commits follow our message guidelines

### Submitting a Pull Request

1. Push your branch to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```

2. Create a pull request from your fork to the main repository

3. Fill out the PR template completely:
   - Clear description of changes
   - Link to related issues
   - Breaking changes highlighted
   - Testing approach described

4. Respond to code review feedback promptly

5. Squash commits if requested

### PR Review Process

What reviewers look for:

- **Code Quality**: Clear, maintainable, follows standards
- **Test Coverage**: Comprehensive tests for new functionality
- **Documentation**: Complete and accurate
- **Alignment with Philosophy**: Matches Durable Programming principles
- **Performance**: No unnecessary performance degradation
- **Security**: Safe handling of user input and resources

## Reporting Issues

### Bug Reports

Include:

- **Clear Title**: Describe the issue concisely
- **Ruby Version**: Output of `ruby -v`
- **Gem Version**: Output of `gem list typst-rails`
- **Steps to Reproduce**: Detailed, numbered steps
- **Expected Behavior**: What should happen
- **Actual Behavior**: What actually happens
- **Error Messages**: Full error output with stack trace
- **Sample Code**: Minimal reproduction case

**Example:**

```markdown
### Bug: Renderer fails with large template sources

**Ruby Version:** ruby 3.2.0
**Gem Version:** typst-rails 0.1.0

**Steps to Reproduce:**
1. Create a Typst template larger than 15MB
2. Initialize renderer with this template
3. Call renderer.render

**Expected:** Should process or show clear error message
**Actual:** Silently fails with no error

**Error Output:**
```
ArgumentError: Source is too large
```

**Sample Code:**
```ruby
large_source = "content" * 5_000_000
renderer = TypstRails::Renderer.new(large_source)
renderer.render
```
```

### Feature Requests

Include:

- **Use Case**: Describe the problem you're trying to solve
- **Proposed Solution**: How you'd like it to work
- **Alternatives**: Other approaches you've considered
- **Impact**: Who benefits and how

## Code of Conduct

### Our Standards

- Be respectful and inclusive
- Welcome newcomers warmly
- Accept constructive criticism gracefully
- Focus on what's best for the community
- Show empathy towards others

### Unacceptable Behavior

- Harassment, discrimination, or exclusion
- Personal attacks or trolling
- Publishing others' private information
- Unprofessional conduct

### Enforcement

Violations may be reported to commercial@durableprogramming.com. All reports will be reviewed and investigated confidentially.

## Releasing

Releases are cut from `main` with `bin/release`, which bumps the version,
promotes the `## [Unreleased]` section of `CHANGELOG.md` into a dated release
heading, commits, tags, and pushes.

```bash
bin/release patch --dry-run   # see exactly what would change
bin/release patch             # 0.1.0 -> 0.1.1
bin/release minor             # 0.1.0 -> 0.2.0
bin/release major             # 0.1.0 -> 1.0.0
bin/release 1.2.3             # an explicit version
```

Before it changes anything, the script checks that you are on `main`, the
working tree is clean, the tag does not already exist, `main` matches
`origin/main`, and the `## [Unreleased]` section is not empty. It then runs
RuboCop and the test suite.

Pushing the `vX.Y.Z` tag triggers `.github/workflows/release.yml`, which
re-runs the checks, publishes the gem to RubyGems via
[trusted publishing](https://guides.rubygems.org/trusted-publishing/) (OIDC,
so no API key is stored in the repository), and opens a GitHub Release
carrying that version's changelog entry.

Watch the run with `gh run watch`.

### One-time setup

`bin/setup-github` applies the repository settings (description, topics, merge
strategy, branch protection). Run `bin/setup-github --dry-run` first to see
what it would change.

Trusted publishing has to be linked once on rubygems.org before the first
release; `bin/setup-github` prints the exact steps at the end of its output.

## Questions?

- **Documentation**: [API Documentation](https://rubydoc.info/gems/typst-rails)
- **Issues**: [GitHub Issues](https://github.com/durable-oss/typst-rails/issues)
- **Email**: commercial@durableprogramming.com

---

## Philosophy Alignment

All contributions should align with the [Durable Philosophy](README.md#the-durable-philosophy):

- **Solving Real Problems**: Address genuine user needs
- **Long-Term Sustainability**: Write maintainable code
- **Quality and Reliability**: Comprehensive testing
- **Pragmatism and Simplicity**: Favor proven solutions
- **Transparency and Honesty**: Clear communication
- **Developer Experience**: Create efficient, enjoyable tools
- **Continuous Improvement**: Iterate based on feedback

Thank you for contributing to `typst-rails` and helping make it a better tool for the Ruby community!
