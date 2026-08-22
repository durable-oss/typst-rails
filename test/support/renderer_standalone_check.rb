# frozen_string_literal: true

# Run in a fresh subprocess to verify that TypstRails::Renderer works when
# only "typst_rails/renderer" is required directly, without the top-level
# "typst_rails" (which defines TypstRails.configuration). This mirrors how
# e2e-tests/run_e2e_tests.rb and other standalone scripts load the gem.
# Prints "OK" and exits 0 on success.

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "typst_rails/renderer"

raise "TypstRails.configuration should not be defined in this scenario" if TypstRails.respond_to?(:configuration)

renderer = TypstRails::Renderer.new("= Hello")
pdf = renderer.render(nil, {})

raise "Expected PDF bytes" unless pdf.start_with?("%PDF")

puts "OK"
