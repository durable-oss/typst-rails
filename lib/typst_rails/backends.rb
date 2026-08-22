# frozen_string_literal: true

require "typst_rails/backends/base"
require "typst_rails/backends/registry"
require "typst_rails/backends/cli"
require "typst_rails/backends/gem"

module TypstRails
  module Backends
    # The `typst` gem, when installed, compiles in-process and is preferred
    # over shelling out. The CLI backend is always registered as a fallback.
    Registry.register(:gem, Gem.new)
    Registry.register(:cli, Cli.new)
  end
end
