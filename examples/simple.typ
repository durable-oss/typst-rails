#set page(margin: 1in)
#set text(font: "FS Jack", size: 12pt)
#set par(justify: true)

= Introduction

This is a simple Typst document demonstrating basic formatting capabilities.

== Text Formatting

You can make text *bold*, _italic_, or `monospace`. You can also combine formatting like *_bold and italic_*.

== Lists

Here's an unordered list:
- First item
- Second item
  - Nested item
  - Another nested item
- Third item

And here's a numbered list:
1. First step
2. Second step
3. Third step

== Math

Typst supports inline math like $x^2 + y^2 = z^2$ and display math:

$ integral_0^infinity e^(-x^2) dif x = sqrt(pi)/2 $

== Code

Here's a code block:

```python
def hello_world():
    print("Hello, World!")
    return 42
```

== Table

#table(
  columns: 3,
  [Name], [Age], [City],
  [Alice], [25], [New York],
  [Bob], [30], [London],
  [Charlie], [35], [Tokyo]
)

This document showcases the basic features of Typst for creating formatted documents.
