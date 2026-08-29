#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs inside the fresh-install container after `gem install ./typst-rails-*.gem`
# (built from the current checkout, not loaded via a Bundler path: dependency).
# Proves the packaged gem works standalone with no framework and no explicit
# backend configuration -- what a brand new user gets out of the box.

require "typst_rails"

def fail!(message)
  warn "FAIL: #{message}"
  exit 1
end

source = <<~TYPST
  = Fresh Install Report

  #let data = json("typst_data.json")

  Hello, #data.name!
TYPST

pdf = TypstRails::Renderer.new(source).render(nil, { name: "World" })

fail!("compiled output does not start with the PDF magic bytes") unless pdf.start_with?("%PDF")
fail!("compiled output is suspiciously small (#{pdf.bytesize} bytes)") if pdf.bytesize < 100

puts "OK: fresh gem install rendered a #{pdf.bytesize}-byte PDF"
