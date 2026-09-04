# frozen_string_literal: true

# Run in a fresh subprocess to verify that TypstRails::Railtie registers the
# :typ template handler with ActionView and loads the gem's rake tasks.
#
# Rails is not a development dependency of this gem, so this script stands up
# just enough of Rails::Railtie and ActionView to observe the registration.
# Prints "OK" and exits 0 on success.

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

# MARK: - Minimal Rails::Railtie stand-in
#
# Captures the initializer and rake_tasks blocks the Railtie declares so they
# can be run on demand, mirroring what Rails' own booting would do. As in real
# Rails, this state is per-class: a subclass records into its own ivars, so the
# assertions below read from TypstRails::Railtie rather than the base class.
module Rails
  class Railtie
    class << self
      def initializers
        @initializers ||= {}
      end

      def rake_task_blocks
        @rake_task_blocks ||= []
      end

      def initializer(name, &block)
        initializers[name] = block
      end

      def rake_tasks(&block)
        rake_task_blocks << block
      end
    end
  end

  def self.application
    nil
  end
end

# `require "rails/railtie"` must resolve; point it at the constants above.
$LOADED_FEATURES << File.expand_path("rails/railtie.rb")
module Kernel
  alias original_require_for_railtie_check require

  def require(name)
    return true if name == "rails/railtie"

    original_require_for_railtie_check(name)
  end
end

# MARK: - Minimal ActionView stand-in

module ActiveSupport
  def self.on_load(name, &block)
    (@on_load_blocks ||= Hash.new { |h, k| h[k] = [] })[name] << block
  end

  def self.run_load_hooks(name, context)
    (@on_load_blocks ||= Hash.new { |h, k| h[k] = [] })[name].each do |block|
      context.instance_eval(&block)
    end
  end
end

module ActionView
  class Template
    class << self
      def registered_handlers
        @registered_handlers ||= {}
      end

      def register_template_handler(extension, handler)
        registered_handlers[extension] = handler
      end
    end
  end
end

require "typst_rails/railtie"

# MARK: - Assertions

initializer = TypstRails::Railtie.initializers["typst_rails.register_template_handler"]
raise "Railtie did not declare the register_template_handler initializer" unless initializer

# Nothing should be registered until the action_view load hook fires.
unless ActionView::Template.registered_handlers.empty?
  raise "handler was registered before the action_view load hook ran"
end

initializer.call
ActiveSupport.run_load_hooks(:action_view, ActionView::Template)

handler = ActionView::Template.registered_handlers[:typ]
raise "the :typ template handler was not registered" unless handler
raise "expected TypstRails::Handler, got #{handler.inspect}" unless handler == TypstRails::Handler

# The rake_tasks block must point at a file that actually ships.
raise "Railtie declared no rake_tasks block" if TypstRails::Railtie.rake_task_blocks.empty?

tasks_path = File.expand_path("../../lib/tasks/typst_rails/tasks.rake", __dir__)
raise "rake task file is missing: #{tasks_path}" unless File.exist?(tasks_path)

# Running the block must not raise (it `load`s the .rake file).
require "rake"
TypstRails::Railtie.rake_task_blocks.each(&:call)

puts "OK"
