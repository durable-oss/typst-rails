# frozen_string_literal: true

# Bundler.require loads a gem by its name, "typst-rails", but the library's
# entry point is typst_rails.rb. This file bridges the two, so a plain
# `gem "typst-rails"` line in a Gemfile loads the Railtie and registers the
# .typ template handler.
require "typst_rails"
