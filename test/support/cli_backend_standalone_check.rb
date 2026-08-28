# frozen_string_literal: true

# Run in a fresh subprocess to verify that the :cli backend works when only
# "typst_rails/renderer" is required, without the top-level "typst_rails"
# that defines TypstRails.configuration. Cli#executable_path reads that
# configuration, and safe navigation does not help when the method itself is
# undefined. Prints "OK" and exits 0 on success.

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "typst_rails/renderer"
require "typst_rails/backends/cli"

raise "TypstRails.configuration should not be defined in this scenario" if TypstRails.respond_to?(:configuration)

backend = TypstRails::Backends::Cli.new

# The result depends on whether Typst is installed; what matters is that
# asking does not raise NoMethodError.
backend.available?

# An explicit path must still take precedence without consulting configuration.
explicit = TypstRails::Backends::Cli.new(executable_path: "/no/such/typst-binary")
raise "Expected an explicitly-pathed backend to be unavailable" if explicit.available?

puts "OK"
