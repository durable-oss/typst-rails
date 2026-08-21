# E2E Test Examples

This document shows example outputs from the E2E test templates to help you understand what each test validates.

## Test 01: Text Escaping

**Input** (`01_text_escaping.typ.erb`):
```erb
<% price = "$100" %>
The price is <%= escape_typst(price) %>
```

**Generated Typst** (`01_text_escaping.typ`):
```typst
The price is \$100
```

**What it tests:**
- Special Typst characters are properly escaped
- Document compiles without treating `$` as math delimiter

## Test 02: HTML Conversion

**Input** (`02_html_conversion.typ.erb`):
```erb
<% html = "<h1>Title</h1><p><strong>Bold</strong> text</p>" %>
<%= html_to_typst(html) %>
```

**Generated Typst** (`02_html_conversion.typ`):
```typst
= Title

*Bold* text
```

**What it tests:**
- HTML headings convert to Typst headings
- HTML bold converts to Typst bold
- HTML structure is preserved in Typst syntax

## Test 03: Markdown Conversion

**Input** (`03_markdown_conversion.typ.erb`):
```erb
<% md = "# Title\n**bold** and [link](https://example.com)" %>
<%= markdown_to_typst(md) %>
```

**Generated Typst** (`03_markdown_conversion.typ`):
```typst
= Title

*bold* and #link("https://example.com")[link]
```

**What it tests:**
- Markdown headers convert to Typst headers
- Markdown emphasis converts to Typst emphasis
- Markdown links convert to Typst link syntax

## Test 04: Include Markdown

**Input** (`04_include_markdown.typ.erb`):
```erb
<% fixture_path = File.join(__dir__, "../fixtures/sample.md") %>
<%= include_markdown(fixture_path) %>
```

**Fixture** (`fixtures/sample.md`):
```markdown
# External Content
This is from an external file.
```

**Generated Typst** (`04_include_markdown.typ`):
```typst
= External Content

This is from an external file.
```

**What it tests:**
- External Markdown files can be loaded
- File content is converted to Typst
- Relative paths work correctly

## Test 05: Complex Template

**Input** (`05_complex_template.typ.erb`):
```erb
<%
  title = "Invoice #12345"
  customer = "John Doe & Associates"
  items = [
    { name: "Service", price: "$100", description: "Work <strong>completed</strong>" }
  ]
%>

= <%= escape_typst(title) %>

Customer: <%= escape_typst(customer) %>

<% items.each do |item| %>
*<%= escape_typst(item[:name]) %>*: <%= escape_typst(item[:price]) %>

<%= html_to_typst(item[:description]) %>
<% end %>
```

**Generated Typst** (`05_complex_template.typ`):
```typst
= Invoice \#12345

Customer: John Doe \& Associates

*Service*: \$100

Work *completed*
```

**What it tests:**
- Multiple helpers work together
- ERB loops integrate properly
- Real-world invoice scenario
- Mixed content types (text, HTML, special chars)

## Running a Single Test

To test just one template:

```bash
# Edit run_e2e_tests.rb to process only one file
ruby -e "
  require_relative 'e2e-tests/run_e2e_tests.rb'
  runner = E2ETestRunner.new
  runner.send(:run_test, '01_text_escaping', 'e2e-tests/templates/01_text_escaping.typ.erb')
"
```

Or manually:

```bash
# 1. Process ERB
ruby -rerb -I lib -r durable/typst/helpers -e "
  include TypstRails::Helpers
  erb = ERB.new(File.read('e2e-tests/templates/01_text_escaping.typ.erb'), trim_mode: '-')
  puts erb.result(binding)
" > output.typ

# 2. Compile with Typst
typst compile output.typ output.pdf

# 3. View result
open output.pdf
```

## Debugging Failed Tests

If a test fails:

1. **Check the .typ file** in `e2e-tests/output/`
   - Does the ERB processing look correct?
   - Are special characters escaped?
   - Is the Typst syntax valid?

2. **Try compiling manually**:
   ```bash
   typst compile e2e-tests/output/01_text_escaping.typ test.pdf
   ```
   - Does Typst show specific errors?
   - What line is causing the issue?

3. **Check the template**:
   - Are helper methods called correctly?
   - Are variables defined before use?
   - Are file paths correct for `include_markdown`?

4. **Verify Typst installation**:
   ```bash
   typst --version
   which typst
   ```

## Adding Your Own Test

Create `e2e-tests/templates/06_my_test.typ.erb`:

```erb
<%# My custom test %>
<% data = "Test data with #special chars" %>

= My Test

<%= escape_typst(data) %>

<% html = "<p>HTML <strong>content</strong></p>" %>
<%= html_to_typst(html) %>
```

Run:
```bash
bundle exec rake e2e
```

Check output:
```bash
ls e2e-tests/output/06_my_test.*
# Should see: 06_my_test.typ and 06_my_test.pdf
```

## Expected Output Structure

After running E2E tests, you should see:

```
e2e-tests/output/
├── 01_text_escaping.typ     # Intermediate Typst source
├── 01_text_escaping.pdf     # Final PDF (verify visually)
├── 02_html_conversion.typ
├── 02_html_conversion.pdf
├── 03_markdown_conversion.typ
├── 03_markdown_conversion.pdf
├── 04_include_markdown.typ
├── 04_include_markdown.pdf
├── 05_complex_template.typ
└── 05_complex_template.pdf
```

## Visual Verification

Always visually inspect the generated PDFs:

```bash
# macOS
open e2e-tests/output/*.pdf

# Linux
xdg-open e2e-tests/output/*.pdf

# Windows
start e2e-tests/output/*.pdf
```

Look for:
- Correct text rendering
- Proper escaping (no raw `#` or `$` in wrong contexts)
- Formatted headings, bold, italic
- Links rendered correctly
- No compilation artifacts or errors

## Performance Benchmarking

Time the E2E tests:

```bash
time bundle exec rake e2e
```

Typical timings:
- 5 templates × ~0.5s each = ~2.5s total
- Plus overhead: ~3-4s end-to-end

If much slower:
- Check Typst version (newer = faster)
- Check system resources
- Review template complexity
