# Testing Guide

This document provides information about the testing infrastructure and defensive programming practices in the Durable Typst gem.

## Test Suite

The gem includes comprehensive unit tests covering all major functionality:

### Test Files

- `test/durable/typst/framework_detection_test.rb` - Framework detection logic
- `test/durable/typst/renderer_test.rb` - Core renderer functionality
- `test/durable/typst/renderer_error_test.rb` - Error handling and edge cases
- `test/durable/typst/helpers_test.rb` - Helper method functionality

### Running Tests

```bash
# Run all tests
bundle exec rake test

# Run a specific test file
ruby -Ilib:test test/durable/typst/renderer_test.rb

# Run with verbose output
TESTOPTS="-v" bundle exec rake test
```

### Code Coverage

SimpleCov is configured to track code coverage:

```bash
bundle exec rake test
open coverage/index.html
```

Coverage reports are generated in the `coverage/` directory.

## Defensive Programming Practices

The gem implements extensive defensive programming to ensure reliability and security:

### Input Validation

1. **Nil Checks**: All public methods validate that required parameters are not nil
2. **Type Checks**: Parameters are validated to be the expected type (String, Hash, etc.)
3. **Size Limits**: Source code size is limited to 10MB to prevent memory issues
4. **Empty String Checks**: Methods validate that strings are not empty when required

### Error Handling

1. **Specific Exceptions**: Uses `TypstRails::Error` for gem-specific errors
2. **Error Wrapping**: External errors are caught and wrapped with context
3. **Graceful Degradation**: Cleanup code uses rescue blocks to continue despite errors
4. **Detailed Messages**: Error messages include context and suggestions for resolution

### Resource Management

1. **Temp File Cleanup**: All temporary files are cleaned up in ensure blocks
2. **File Handle Closing**: Files are explicitly closed before external tools access them
3. **Error Recovery**: Cleanup continues even if individual operations fail

### Security

1. **Text Escaping**: `escape_typst` prevents injection attacks
2. **Path Validation**: File operations validate paths exist and are accessible
3. **JSON Serialization**: Handles serialization errors gracefully

### Examples from the Code

#### Input Validation
```ruby
def initialize(source)
  raise ArgumentError, "Source cannot be nil" if source.nil?
  @source = source.to_s

  if @source.bytesize > MAX_SOURCE_SIZE
    raise ArgumentError, "Source is too large..."
  end
end
```

#### Error Handling
```ruby
begin
  _stdout_str, stderr_str, status = Open3.capture3(*cmd)
rescue Errno::ENOENT => e
  raise Error, "Typst executable not found. Please ensure Typst is installed..."
rescue StandardError => e
  raise Error, "Failed to execute Typst compiler: #{e.message}"
end
```

#### Resource Cleanup
```ruby
ensure
  begin
    temp_typ_file.unlink if temp_typ_file&.path && File.exist?(temp_typ_file.path)
  rescue StandardError => e
    warn "Failed to clean up temp Typst file: #{e.message}"
  end
end
```

## Test Helpers

The test suite includes helper methods for common testing patterns:

- `mock_successful_typst_compilation` - Mocks successful Typst execution
- `mock_failed_typst_compilation` - Mocks failed compilation
- `with_defined_constant` - Temporarily defines a constant for testing
- `with_undefined_constant` - Temporarily removes a constant
- `create_temp_typst_file` - Creates temporary Typst files

## Continuous Integration

Add these steps to your CI pipeline:

```yaml
- name: Install dependencies
  run: bundle install

- name: Run tests
  run: bundle exec rake test

- name: Run RuboCop
  run: bundle exec rake rubocop

- name: Check coverage
  run: bundle exec rake test && [ -f coverage/.resultset.json ]
```

## Adding New Tests

When adding new functionality:

1. Create tests for the happy path
2. Create tests for error conditions
3. Test with nil, empty, and invalid inputs
4. Test resource cleanup
5. Test with different framework environments (Rails, Rage, Sinatra, plain Ruby)

Example test structure:

```ruby
def test_new_feature_with_valid_input
  # Arrange
  input = "valid input"

  # Act
  result = subject.new_feature(input)

  # Assert
  assert_equal expected, result
end

def test_new_feature_with_nil_input
  error = assert_raises(ArgumentError) do
    subject.new_feature(nil)
  end
  assert_equal "Expected error message", error.message
end
```

## Performance Testing

For performance-critical code paths, consider adding benchmarks:

```ruby
require 'benchmark'

Benchmark.bm do |x|
  x.report("render:") do
    1000.times { renderer.render(nil, data) }
  end
end
```

## Security Testing

Always test security-related functionality:

```ruby
def test_escape_typst_escapes_code_marker
  result = escape_typst('#import "@preview/evil": *')
  refute_includes result, '#import'
end
```
