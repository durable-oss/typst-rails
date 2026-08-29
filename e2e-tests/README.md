# End-to-End Tests

This directory contains end-to-end tests that verify the complete functionality of Typst Rails by:

1. Processing ERB templates with all helper methods
2. Generating Typst source code
3. Compiling to actual PDF files using the Typst compiler
4. Validating the generated PDFs

## Prerequisites

**Typst must be installed** on your system to run these tests.

Install Typst:
- macOS: `brew install typst`
- Linux: Download from https://github.com/typst/typst/releases
- Windows: Download from https://github.com/typst/typst/releases

Verify installation:
```bash
typst --version
```

## Directory Structure

```
e2e-tests/
├── templates/          # ERB templates to test
│   ├── 01_text_escaping.typ.erb
│   ├── 02_html_conversion.typ.erb
│   ├── 03_markdown_conversion.typ.erb
│   ├── 04_include_markdown.typ.erb
│   └── 05_complex_template.typ.erb
├── fixtures/           # Test data files
│   └── sample.md
├── output/            # Generated files (gitignored)
│   ├── *.typ         # Intermediate Typst source
│   └── *.pdf         # Final PDFs
├── docker/            # Docker-based backend matrix tests (rake e2e:docker)
│   ├── docker-compose.yml
│   ├── Dockerfile.*  # One per backend scenario
│   ├── scenarios/    # Smoke tests run inside the containers
│   └── README.md
├── run_e2e_tests.rb  # Test runner script
└── README.md         # This file
```

## Running the Tests

### Using Rake (recommended)

```bash
# Run E2E tests only
bundle exec rake e2e

# Run all tests (unit + E2E)
bundle exec rake test_all

# Clean up generated outputs
bundle exec rake clean_e2e
```

### Using the Script Directly

```bash
# Run from project root
./e2e-tests/run_e2e_tests.rb

# Or with Ruby
ruby e2e-tests/run_e2e_tests.rb
```

## Test Coverage

### Test 01: Text Escaping (`01_text_escaping.typ.erb`)
Tests the `escape_typst` helper:
- Escaping special Typst characters: `# $ * _ [ ] \ < > { } @`
- Handling empty strings and nil values
- Multiple escapes in context

### Test 02: HTML Conversion (`02_html_conversion.typ.erb`)
Tests HTML to Typst conversion:
- `html_to_markdown` - Converts HTML to Markdown
- `html_to_typst` - Direct HTML to Typst conversion
- Complex HTML structures (headings, lists, links, emphasis)

### Test 03: Markdown Conversion (`03_markdown_conversion.typ.erb`)
Tests `markdown_to_typst` helper:
- Headers (H1-H6)
- Bold and italic text (multiple syntaxes)
- Links and images
- Inline code
- Lists

### Test 04: Include Markdown (`04_include_markdown.typ.erb`)
Tests `include_markdown` helper:
- Reading external Markdown files
- Converting loaded content to Typst
- Path resolution

### Test 05: Complex Template (`05_complex_template.typ.erb`)
Comprehensive real-world scenario:
- Multiple helpers combined
- ERB loops and conditionals
- Dynamic data from variables
- Invoice-style document layout
- Page breaks and formatting
- URL encoding
- External file inclusion

## Output Files

After running tests, check the `output/` directory:

- `.typ` files - Intermediate Typst source (useful for debugging)
- `.pdf` files - Final compiled PDFs (verify visually)

Example:
```bash
ls -lh e2e-tests/output/
# 01_text_escaping.typ
# 01_text_escaping.pdf
# 02_html_conversion.typ
# 02_html_conversion.pdf
# ...
```

## Test Runner Features

The `run_e2e_tests.rb` script provides:

- ✓ Automatic discovery of all `.typ.erb` templates
- ✓ ERB processing with helper methods available
- ✓ Typst compilation with error handling
- ✓ PDF validation (checks magic bytes and file size)
- ✓ Detailed progress reporting
- ✓ Summary with pass/fail/skip counts
- ✓ Graceful handling when Typst is not installed

## Interpreting Results

### Success
```
✓ ERB processed successfully
✓ PDF generated successfully
✓ PDF validation passed
✅ test_name PASSED
```

### Failure
```
❌ test_name FAILED
   Error: Typst compilation failed
```

Common failures:
- Typst not installed → Install Typst
- Syntax errors in template → Check `.typ` file in output/
- Helper method errors → Check ERB template

### Skipped
```
⚠️  test_name SKIPPED: Typst executable not found
```

Tests are skipped if Typst is not installed. This allows CI/CD to run unit tests even if Typst is not available.

## Adding New Tests

1. Create a new template file: `templates/XX_test_name.typ.erb`
2. Add ERB code using the helper methods
3. Run the test suite: `bundle exec rake e2e`
4. Check the output PDF in `output/XX_test_name.pdf`

Template naming convention: `NN_description.typ.erb` where NN is a number (01, 02, etc.)

## Continuous Integration

For CI environments without Typst:

```yaml
# Option 1: Install Typst in CI
- name: Install Typst
  run: |
    wget https://github.com/typst/typst/releases/download/v0.11.0/typst-x86_64-unknown-linux-musl.tar.xz
    tar xf typst-x86_64-unknown-linux-musl.tar.xz
    sudo mv typst-x86_64-unknown-linux-musl/typst /usr/local/bin/

- name: Run E2E tests
  run: bundle exec rake e2e

# Option 2: Skip E2E tests if Typst not available
- name: Run tests
  run: bundle exec rake test  # Unit tests only
```

## Troubleshooting

### "Typst executable not found"
- Install Typst: https://github.com/typst/typst
- Verify: `typst --version`
- Check PATH: `which typst`

### "PDF validation failed"
- Check the `.typ` file in output/ for syntax errors
- Try compiling manually: `typst compile output/test.typ output/test.pdf`

### "ERB processing failed"
- Check template syntax
- Verify helper methods are available
- Check variable names and paths

### Empty or corrupted PDFs
- Review the `.typ` source file
- Check for Typst syntax errors
- Verify data being passed to helpers

## Manual Testing

You can manually test templates:

```bash
# 1. Process ERB manually
ruby -rerb -e "puts ERB.new(File.read('templates/01_text_escaping.typ.erb')).result" > output/manual.typ

# 2. Compile with Typst
typst compile output/manual.typ output/manual.pdf

# 3. View PDF
open output/manual.pdf  # macOS
xdg-open output/manual.pdf  # Linux
```

## Contributing

When adding new helpers or modifying existing ones:

1. Add E2E test template demonstrating the feature
2. Run the E2E tests to verify
3. Check the generated PDF visually
4. Commit both template and reference output (if applicable)
