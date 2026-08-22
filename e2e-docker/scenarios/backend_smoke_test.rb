#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs inside each backend-matrix container (see ../docker-compose.yml) to prove
# TypstRails resolves the right compilation backend for that container's
# environment and actually produces a PDF (or fails the way it's supposed to).
#
# Controlled by two env vars set per-container:
#   EXPECT_BACKEND   - "gem", "cli", or "none" (compilation must fail)
#   EXPECT_ERROR     - if set, EXPECT_BACKEND must be "none"; asserts the
#                      TypstRails::Error message includes this substring

require "typst_rails"

expect_backend = ENV.fetch("EXPECT_BACKEND")
expect_error = ENV.fetch("EXPECT_ERROR", nil)

def fail!(message)
  warn "FAIL: #{message}"
  exit 1
end

if expect_backend == "none"
  begin
    TypstRails::Renderer.new("= Hello").render(nil, {})
    fail!("expected compilation to raise TypstRails::Error, but it succeeded")
  rescue TypstRails::Error => e
    if expect_error && !e.message.include?(expect_error)
      fail!("error message missing #{expect_error.inspect}: #{e.message}")
    end

    puts "OK: compilation failed as expected (#{e.message.lines.first&.strip})"
  end
  exit 0
end

resolved = TypstRails::Backends::Registry.resolve(:auto)
resolved_name = TypstRails::Backends::Registry.backends.key(resolved) || resolved.class.name

unless resolved_name.to_s == expect_backend
  fail!("expected backend #{expect_backend.inspect}, auto-detection picked #{resolved_name.inspect}")
end

pdf = TypstRails::Renderer.new("= Hello from #{expect_backend}\n\nThis PDF was compiled inside Docker.").render(nil, {})

fail!("compiled output does not start with the PDF magic bytes") unless pdf.start_with?("%PDF")
fail!("compiled output is suspiciously small (#{pdf.bytesize} bytes)") if pdf.bytesize < 100

puts "OK: backend=#{resolved_name} produced a #{pdf.bytesize}-byte PDF"
