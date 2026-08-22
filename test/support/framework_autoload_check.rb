# frozen_string_literal: true

# Run in a fresh subprocess to verify that requiring "typst_rails" with a
# framework constant already defined triggers that framework's integration
# require + setup (typst_rails.rb lines 10-18). Prints "OK" and exits 0.
#
# Usage: ruby framework_autoload_check.rb <rage|sinatra>

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

framework = ARGV.fetch(0)

case framework
when "rage"
  module Rage
    module Application; end

    def self.configure
      yield(nil)
    end
  end
when "sinatra"
  module Sinatra
    class Base
      def self.fake_sinatra_base?
        true
      end
    end
  end
else
  raise "unknown framework: #{framework}"
end

require "typst_rails"

case framework
when "rage"
  raise "TypstRails::RageIntegration was not loaded" unless defined?(TypstRails::RageIntegration)
when "sinatra"
  raise "TypstRails::SinatraIntegration was not loaded" unless defined?(TypstRails::SinatraIntegration)
  raise "Sinatra::Base#typst was not defined" unless Sinatra::Base.method_defined?(:typst)
end

puts "OK"
