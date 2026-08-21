# Security Policy

## Supported Versions

We actively support the following versions with security updates:

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

**Do not report security vulnerabilities through public GitHub issues.**

Security vulnerabilities should be reported privately to help protect users while a fix is being developed.

### How to Report

Please report security vulnerabilities to: **security@durableprogramming.com**

### What to Include

To help us understand and address the vulnerability quickly, please include:

1. **Description**: A clear description of the vulnerability
2. **Impact**: What the vulnerability could allow an attacker to do
3. **Steps to Reproduce**: Detailed steps to reproduce the issue
4. **Affected Versions**: Which versions of the gem are affected
5. **Suggested Fix**: If you have a proposed solution (optional)
6. **Proof of Concept**: Code demonstrating the vulnerability (if applicable)

### What to Expect

- **Initial Response**: Within 48 hours of your report
- **Status Updates**: Every 3-5 business days on our progress
- **Disclosure Timeline**: We aim to release a fix within 90 days
- **Coordinated Disclosure**: We will work with you on responsible disclosure timing
- **Credit**: We will publicly acknowledge your contribution (unless you prefer to remain anonymous)

## Security Best Practices

When using `typst-rails`:

### Input Validation

- **Template Sources**: Be cautious when accepting user-provided Typst template sources
- **Data Binding**: Validate and sanitize data passed to templates
- **File Paths**: Never allow user input to directly control file paths

### Dependency Management

- **Keep Updated**: Regularly update to the latest version for security fixes
- **Audit Dependencies**: Run `bundle audit` or similar tools to check for known vulnerabilities
- **Review Updates**: Review CHANGELOG.md for security-related changes

### Configuration

- **Executable Path**: Ensure `typst_executable_path` points to a trusted Typst binary
- **Root Path**: Use `default_root_path` to restrict template file access
- **Environment Isolation**: Run Typst compilation in a sandboxed environment when processing untrusted input

### Template Security

- **Escape User Data**: Always escape user-provided data in templates
- **Sanitize HTML**: Use `sanitize_html` helper when converting HTML to Typst
- **Validate JSON**: Ensure data passed to templates is properly validated

### Example Secure Usage

```ruby
# Good: Sanitize user input before conversion
safe_html = sanitize_html(params[:user_content])
typst_content = html_to_typst(safe_html)

# Good: Escape user-provided text
title = escape_typst(params[:title])

# Bad: Never use unsanitized user input
# unsafe_content = html_to_typst(params[:user_content]) # DON'T DO THIS
```

## Known Security Considerations

### Typst Command Execution

This gem executes the Typst command-line tool to compile templates. Ensure:

1. The Typst executable is from a trusted source
2. The executable path is not modifiable by untrusted users
3. Template sources are validated before compilation

### Temporary File Handling

The gem creates temporary files for compilation:

- Files are created in system temp directories with random names
- Files are automatically cleaned up after compilation
- File permissions are set to restrict access to the current user

### Resource Limits

- Template source size is limited to 10MB to prevent memory exhaustion
- Consider implementing additional timeouts for long-running compilations
- Monitor system resources when processing untrusted templates

## Security Audits

- **Last Audit**: Not yet audited
- **Next Scheduled Audit**: To be determined
- **Dependency Scanning**: Automated via GitHub Dependabot

## Vulnerability Disclosure Policy

We follow responsible disclosure practices:

1. Reporter notifies us privately
2. We acknowledge and investigate
3. We develop and test a fix
4. We release a security update
5. We coordinate public disclosure with the reporter
6. We publish a security advisory

## Contact

For security concerns: **security@durableprogramming.com**

For other questions: **commercial@durableprogramming.com**

---

Thank you for helping keep `typst-rails` and its users safe!
