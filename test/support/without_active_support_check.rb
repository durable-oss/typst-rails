# frozen_string_literal: true

# Run in a fresh subprocess (no ActiveSupport loaded) to verify that
# TypstRails::Renderer defines a Hash#symbolize_keys shim when ActiveSupport
# is unavailable. Prints "OK" and exits 0 on success.

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

module Kernel
  alias original_require_for_shim_test require

  def require(name)
    raise LoadError, "cannot load such file -- #{name}" if name.start_with?("active_support")

    original_require_for_shim_test(name)
  end
end

require "typst_rails/renderer"

raise "Hash#symbolize_keys shim was not defined" unless {}.respond_to?(:symbolize_keys)
raise "shim did not symbolize keys correctly" unless { "a" => 1 }.symbolize_keys == { a: 1 }

puts "OK"
