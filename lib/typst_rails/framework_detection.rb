# frozen_string_literal: true

module TypstRails
  # Detects which web framework (if any) is currently loaded
  module FrameworkDetection
    def self.rails?
      defined?(::Rails) && ::Rails.respond_to?(:application)
    end

    def self.rage?
      defined?(::Rage::Application)
    end

    def self.sinatra?
      defined?(::Sinatra::Base)
    end

    def self.detected_framework
      return :rails if rails?
      return :rage if rage?
      return :sinatra if sinatra?

      nil
    end
  end
end
