# E2E Tests Summary

## Overview

The E2E test suite validates the complete Durable Typst workflow by:

1. Processing ERB templates with helper methods
2. Generating Typst source code
3. Compiling to actual PDFs using Typst
4. Validating the generated outputs

## Files Created

```
e2e-tests/
├── README.md                           # Comprehensive E2E testing documentation
├── EXAMPLES.md                         # Example inputs/outputs for each test
├── run_e2e_tests.rb                   # Test runner script (executable)
├── templates/                          # ERB templates to test
│   ├── 01_text_escaping.typ.erb       # Tests escape_typst helper
│   ├── 02_html_conversion.typ.erb     # Tests HTML to Typst conversion
│   ├── 03_markdown_conversion.typ.erb # Tests Markdown to Typst conversion
│   ├── 04_include_markdown.typ.erb    # Tests external file inclusion
│   └── 05_complex_template.typ.erb    # Real-world comprehensive test
├── fixtures/
│   └── sample.md                       # Test data for include_markdown
└── output/                             # Generated files (gitignored)
    ├── .gitkeep
    ├── *.typ                          # Intermediate Typst source
    └── *.pdf                          # Final PDFs
```

## Test Coverage

### Test 01: Text Escaping
- **File**: `01_text_escaping.typ.erb`
- **Tests**: `escape_typst()` helper
- **Validates**:
  - All Typst special characters: `# $ * _ [ ] \ < > { } @`
  - Empty strings and nil handling
  - Multiple escapes in one document

### Test 02: HTML Conversion
- **File**: `02_html_conversion.typ.erb`
- **Tests**: `html_to_markdown()`, `html_to_typst()`
- **Validates**:
  - HTML headings → Typst headings
  - Bold/italic conversion
  - Lists and links

### Test 03: Markdown Conversion
- **File**: `03_markdown_conversion.typ.erb`
- **Tests**: `markdown_to_typst()`
- **Validates**:
  - Headers H1-H6
  - Bold and italic (multiple syntaxes)
  - Links and images
  - Inline code
  - Nested structures

### Test 04: Include Markdown
- **File**: `04_include_markdown.typ.erb`
- **Tests**: `include_markdown()`
- **Validates**:
  - Reading external files
  - Path resolution
  - Content conversion
  - Error handling for missing files

### Test 05: Complex Template
- **File**: `05_complex_template.typ.erb`
- **Tests**: All helpers combined
- **Validates**:
  - Real-world invoice scenario
  - ERB loops and conditionals
  - Multiple helpers working together
  - Page breaks and formatting
  - Dynamic data from variables

## Running Tests

```bash
# Run E2E tests only
bundle exec rake e2e

# Run all tests (unit + E2E)
bundle exec rake test_all

# Clean generated outputs
bundle exec rake clean_e2e

# Direct script execution
./e2e-tests/run_e2e_tests.rb
```

## Requirements

- Ruby 2.7+
- Bundler with gem dependencies
- **Typst compiler** (install from https://github.com/typst/typst)

Tests gracefully skip if Typst is not installed, showing a warning instead of failing.

## Test Runner Features

The `run_e2e_tests.rb` script provides:

- ✓ Auto-discovery of `.typ.erb` templates
- ✓ ERB processing with helpers available in binding
- ✓ Typst compilation with subprocess execution
- ✓ PDF validation (magic bytes, file size)
- ✓ Detailed progress reporting
- ✓ Pass/fail/skip summary
- ✓ Graceful handling of missing Typst
- ✓ Error messages with context

## Output Validation

For each test, the runner:

1. **ERB Processing**: Converts `.typ.erb` → `.typ` source
2. **Compilation**: Runs `typst compile input.typ output.pdf`
3. **Size Check**: Ensures PDF is > 100 bytes
4. **Magic Bytes**: Verifies PDF starts with `%PDF`
5. **Visual Verification**: User can open PDFs to inspect

## Example Output

```
================================================================================
Running End-to-End Tests for Durable Typst
================================================================================

Output directory: /path/to/e2e-tests/output

--------------------------------------------------------------------------------
Test: 01_text_escaping
--------------------------------------------------------------------------------
✓ ERB processed successfully
  Typst source: /path/to/output/01_text_escaping.typ
✓ PDF generated successfully
  PDF output: /path/to/output/01_text_escaping.pdf
  File size: 2847 bytes
✓ PDF validation passed
✅ 01_text_escaping PASSED

[... more tests ...]

================================================================================
Test Summary
================================================================================

Total:   5
Passed:  5 ✅
Failed:  0 ❌
Skipped: 0 ⚠️
```

## Integration with CI/CD

### With Typst Installed

```yaml
- name: Install Typst
  run: |
    wget https://github.com/typst/typst/releases/download/v0.11.0/typst-x86_64-unknown-linux-musl.tar.xz
    tar xf typst-x86_64-unknown-linux-musl.tar.xz
    sudo mv typst-x86_64-unknown-linux-musl/typst /usr/local/bin/

- name: Run all tests
  run: bundle exec rake test_all
```

### Without Typst (Unit tests only)

```yaml
- name: Run unit tests
  run: bundle exec rake test
```

E2E tests will be skipped with a warning if Typst is not available.

## Debugging

If tests fail:

1. Check the `.typ` file in `output/` directory
2. Try manual compilation: `typst compile output/test.typ test.pdf`
3. Review ERB template for syntax errors
4. Verify helper method usage
5. Check file paths for `include_markdown`

## Benefits

1. **Real Compilation**: Actually runs Typst, catches real errors
2. **Visual Verification**: Generated PDFs can be inspected
3. **Comprehensive**: Tests all helpers in realistic scenarios
4. **CI-Friendly**: Gracefully handles missing Typst
5. **Fast**: ~3-4 seconds for all tests
6. **Debuggable**: Intermediate `.typ` files available for inspection
7. **Extensible**: Easy to add new test templates

## Maintenance

When adding new helpers:

1. Create a new template file: `templates/06_new_feature.typ.erb`
2. Add fixture data if needed in `fixtures/`
3. Run: `bundle exec rake e2e`
4. Visually verify the PDF
5. Document in EXAMPLES.md

## Known Limitations

- Requires Typst installation (not pure Ruby)
- Tests skip if Typst unavailable (by design)
- Visual verification is manual (automated would require PDF parsing)
- Platform-dependent (Typst must support the OS)

## Future Enhancements

Potential improvements:

- [ ] Automated PDF text extraction for assertions
- [ ] Parallel test execution
- [ ] Benchmark mode for performance testing
- [ ] Screenshot generation from PDFs
- [ ] Compare PDFs against reference outputs
- [ ] Docker container with Typst pre-installed
