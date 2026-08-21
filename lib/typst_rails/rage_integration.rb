# frozen_string_literal: true

module TypstRails
  # Integration for Rage framework
  module RageIntegration
    def self.setup
      return unless defined?(::Rage)

      require "typst_rails/renderer"

      # Register Typst handler for Rage
      ::Rage.configure do |config|
        # Rage uses a similar template system to Rails
        # We can register our handler here when Rage's template system is available
      end
    end
  end
end
