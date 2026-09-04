# frozen_string_literal: true

module TypstRails
  # Detects which web framework (if any) is currently loaded.
  #
  # Each predicate returns a real +true+ or +false+. `defined?` yields a
  # String or nil rather than a boolean, so the results are coerced: callers
  # that compare against +false+ or serialize the value would otherwise see
  # nil when the framework is absent.
  module FrameworkDetection
    # @return [Boolean] whether Rails is loaded and booted far enough to have
    #   an application object
    def self.rails?
      !!(defined?(::Rails) && ::Rails.respond_to?(:application))
    end

    # @return [Boolean] whether Rage is loaded
    def self.rage?
      !defined?(::Rage::Application).nil?
    end

    # @return [Boolean] whether Sinatra is loaded
    def self.sinatra?
      !defined?(::Sinatra::Base).nil?
    end

    def self.detected_framework
      return :rails if rails?
      return :rage if rage?
      return :sinatra if sinatra?

      nil
    end
  end
end
