# frozen_string_literal: true

require "rails/railtie"

module TypstRails
  class Railtie < ::Rails::Railtie
    initializer "typst_rails.register_template_handler" do
      ActiveSupport.on_load(:action_view) do
        require "typst_rails/handler"
        ActionView::Template.register_template_handler(:typ, TypstRails::Handler)
      end
    end

    rake_tasks do
      load File.expand_path("../tasks/typst_rails/tasks.rake", __dir__)
    end
  end
end
