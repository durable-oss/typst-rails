# frozen_string_literal: true

source "https://rubygems.org"

# Development and runtime dependencies live in the gemspec, per the
# Durable Programming gem convention.
gemspec

# The `typst` gem backs the :gem compilation backend and is needed only to
# test it. It requires Ruby >= 3.0, while this gem supports 2.7, so it lives
# here rather than in the gemspec: a version guard belongs in the Gemfile,
# which is not packaged, not in the gemspec, whose contents must not vary with
# the Ruby that built the gem. The :gem backend tests skip when it is absent.
gem "typst", ">= 0.15", require: false if RUBY_VERSION >= "3.0"
