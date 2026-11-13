# frozen_string_literal: true

require "erb"

module TypstRails
  # Runs a Typst template through ERB in a given scope, for frameworks
  # without an ActionView-style template handler (Sinatra, Rage).
  #
  # As in Rails `.typ` views, output from `<%= %>` is not escaped; use
  # {Helpers#escape_typst} for untrusted values.
  #
  # @api private
  module ErbSource
    # Local names ERB can bind; other keys still reach typst_data.json.
    LOCAL_NAME = /\A[a-z_][a-zA-Z0-9_]*\z/.freeze

    # Defined at module level so the binding it returns closes over no
    # locals of #render, which a same-named template local could clobber.
    BLANK_BINDING = proc { binding }
    private_constant :BLANK_BINDING

    # @param source [String] template source
    # @param scope [Object] self for the template: its instance variables
    #   and methods are visible to ERB
    # @param locals [Hash] exposed to ERB as local variables
    # @return [String] the evaluated Typst source
    def self.render(source, scope, locals = {})
      context = scope.instance_exec(&BLANK_BINDING)
      locals.each do |name, value|
        name = name.to_s
        context.local_variable_set(name, value) if LOCAL_NAME.match?(name)
      end
      ::ERB.new(source, trim_mode: "-").result(context)
    end
  end
end
