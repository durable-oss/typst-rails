# frozen_string_literal: true

require "pathname"
require "stringio"
require "typst_rails/erb_source"
require "typst_rails/framework_detection"
require "typst_rails/helpers"
require "typst_rails/rails_rendering"
require "typst_rails/renderer"

module TypstRails
  # Renders a `.typ` template file to PDF outside a request: in a background
  # job, a mailer, a rake task, or a script.
  #
  # The template runs through ERB first, with +locals+ as local variables,
  # +assigns+ as instance variables, and the {Helpers} methods such as
  # `escape_typst`. Both hashes are also written to typst_data.json, as in
  # the Rails, Sinatra, and Rage integrations.
  #
  # Relative names resolve against +root+, which defaults to `app/views`
  # under Rails.root in a Rails app and to the current directory elsewhere.
  # The `.typ` extension is optional, and `name.pdf.typ` is tried after
  # `name.typ`. A relative name that resolves outside the root, such as
  # `"../secrets"`, raises ArgumentError. Absolute paths are used as given.
  #
  # Rails view helpers, such as route helpers and `render` for partials, are
  # not available. Use {TypstRails.render_with_rails} for templates that
  # need them.
  #
  # @param template [String, Pathname] template name or path, such as
  #   `"reports/monthly"`
  # @param locals [Hash] ERB local variables and typst_data.json entries
  # @param assigns [Hash] ERB instance variables and typst_data.json
  #   entries; locals win on a name clash
  # @param root [String, Pathname, nil] directory relative names resolve against
  # @return [String] binary PDF data
  # @raise [ArgumentError] if the name is blank or resolves outside the root
  # @raise [TypstRails::Error] if the template is missing or compilation fails
  #
  # @example In a background job
  #   pdf = TypstRails.render("reports/monthly", locals: { month: "October" })
  #   File.binwrite("monthly.pdf", pdf)
  #
  # @example In a mailer
  #   attachments["invoice.pdf"] = TypstRails.render("invoices/show", assigns: { invoice: invoice })
  def self.render(template, locals: {}, assigns: {}, root: nil)
    TemplateRendering.render(template, locals: locals, assigns: assigns, root: root)
  end

  # Renders a `.typ` view through a Rails controller and returns the PDF.
  #
  # Unlike {TypstRails.render}, the template goes through ActionView, the
  # same as a `render template:` in a controller action. Rails resolves the
  # name with its own view lookup, and app helpers, route helpers, and
  # partials work. This method calls
  # `controller.render(template:, formats: [:pdf], locals:, assigns:)`.
  #
  # The default controller is ApplicationController when it is defined and
  # inherits from ActionController::Base, otherwise ActionController::Base.
  #
  # Route helpers that build full URLs need a host, from
  # `config.action_controller.default_url_options` or the controller's
  # renderer defaults, because there is no request to take one from.
  #
  # @param template [String, Symbol, Pathname] Rails template name, such as
  #   `"reports/monthly"`
  # @param locals [Hash] view locals
  # @param assigns [Hash] view instance variables
  # @param controller [Class, nil] controller class to render with, such as
  #   `AdminController`
  # @return [String] binary PDF data
  # @raise [TypstRails::Error] if ActionController is not loaded
  # @raise [ActionView::MissingTemplate] if Rails cannot find the template
  #
  # @example In a job
  #   pdf = TypstRails.render_with_rails("invoices/show", assigns: { invoice: invoice })
  def self.render_with_rails(template, locals: {}, assigns: {}, controller: nil)
    RailsRendering.render(template, locals: locals, assigns: assigns, controller: controller)
  end

  # Renders a template and attaches the PDF to +attachable+ by calling
  # `attachable.attach(io:, filename:, content_type:)`.
  #
  # Any object with that method works. An ActiveStorage attachment, such as
  # `report.file` for `has_one_attached :file`, is the usual one.
  #
  # The template renders with {TypstRails.render}, or with
  # {TypstRails.render_with_rails} when +via+ is `:rails`. Other options go
  # to whichever one renders.
  #
  # @param attachable [#attach] receives the PDF
  # @param template [String, Pathname] template name or path
  # @param filename [String] filename to attach the PDF under
  # @param locals [Hash] template locals
  # @param content_type [String] content type to attach the PDF with
  # @param via [Symbol] `:typst_rails` (the default) or `:rails`
  # @param options [Hash] other options for the render method
  #   (`assigns:` and `root:`, or `assigns:` and `controller:`)
  # @return [Object] whatever +attachable.attach+ returns
  # @raise [ArgumentError] if +attachable+ does not respond to `attach`, or
  #   +via+ is unknown
  # @raise [TypstRails::Error] if rendering fails
  #
  # @example
  #   TypstRails.render_and_attach(report.file, "reports/monthly",
  #                                filename: "monthly.pdf", locals: { report: report })
  #
  # @example Through ActionView
  #   TypstRails.render_and_attach(report.file, "reports/monthly",
  #                                filename: "monthly.pdf", via: :rails)
  # rubocop:disable Metrics/ParameterLists -- render options plus the attach options
  def self.render_and_attach(attachable, template, filename:, locals: {}, content_type: "application/pdf",
                             via: :typst_rails, **options)
    raise ArgumentError, "#{attachable.class} does not respond to attach" unless attachable.respond_to?(:attach)

    pdf = case via
          when :typst_rails then render(template, locals: locals, **options)
          when :rails then render_with_rails(template, locals: locals, **options)
          else raise ArgumentError, "via must be :typst_rails or :rails, got #{via.inspect}"
          end
    attachable.attach(io: StringIO.new(pdf), filename: filename, content_type: content_type)
  end
  # rubocop:enable Metrics/ParameterLists

  # Renders `.typ` template files to PDF without a controller or request:
  # from background jobs, mailers, rake tasks, and scripts. Backs
  # {TypstRails.render} and {TypstRails.render_and_attach}, and the Sinatra
  # and Rage helpers.
  #
  # A template file runs through ERB first, then compiles with Typst. Locals
  # are ERB local variables and assigns are instance variables; both are also
  # written to typst_data.json for templates that read it.
  #
  # @api private
  module TemplateRendering
    # File extension of Typst templates.
    EXTENSION = ".typ"

    # Mirrors the `assigns` reader Renderer expects from a view context, so
    # data gets the same JSON conversion (models, dates) as in Rails.
    ViewContext = Struct.new(:assigns)

    # The `self` of a template rendered outside a request: it has the
    # {Helpers} methods and whatever instance variables the assigns set.
    class Scope
      include Helpers

      # @param assigns [Hash] instance variables to set, keyed by name
      #   without the leading `@`
      def initialize(assigns = {})
        assigns.each do |name, value|
          instance_variable_set(:"@#{name}", value) if ErbSource::LOCAL_NAME.match?(name.to_s)
        end
      end
    end

    module_function

    # Resolves a template name, runs it through ERB, and compiles it.
    #
    # @param template [String, Pathname] template path; see {.resolve}
    # @param locals [Hash] ERB local variables, also written to typst_data.json
    # @param assigns [Hash] ERB instance variables, also written to
    #   typst_data.json; locals win on a name clash
    # @param root [String, Pathname, nil] template root; see {.default_root}
    # @return [String] binary PDF data
    # @raise [ArgumentError] if the template resolves outside the root
    # @raise [TypstRails::Error] if the template is missing or compilation fails
    def render(template, locals: {}, assigns: {}, root: nil)
      raise ArgumentError, "locals must be a Hash" unless locals.is_a?(Hash)
      raise ArgumentError, "assigns must be a Hash" unless assigns.is_a?(Hash)

      path = resolve(template, root || default_root)
      render_file(path, Scope.new(assigns), locals, assigns)
    end

    # Renders a template file in a given ERB scope. Shared by the Sinatra and
    # Rage helpers, which pass their route or controller as the scope.
    #
    # @param path [String] path to the template file
    # @param scope [Object] `self` for ERB
    # @param locals [Hash] ERB local variables, also written to typst_data.json
    # @param assigns [Hash] extra data for typst_data.json; locals win on a
    #   name clash
    # @return [String] binary PDF data
    # @raise [TypstRails::Error] if compilation fails
    def render_file(path, scope, locals = {}, assigns = {})
      source = ErbSource.render(File.read(path), scope, locals)
      Renderer.new(source, template: path.to_s).render(ViewContext.new(assigns), locals)
    end

    # Turns a template name into the path of an existing file.
    #
    # Relative names resolve against +root+ and must stay inside it.
    # Absolute paths are used as given. A name without the `.typ` extension
    # matches `name.typ`, or failing that the Rails-style `name.pdf.typ`.
    #
    # @param template [String, Pathname] template name or path
    # @param root [String, Pathname] directory relative names resolve against
    # @return [String] absolute path of the template file
    # @raise [ArgumentError] if the template is blank or resolves outside +root+
    # @raise [TypstRails::Error] if no matching file exists
    #
    # @example
    #   TemplateRendering.resolve("reports/monthly", "app/views")
    #   #=> "/app/app/views/reports/monthly.typ"
    def resolve(template, root)
      name = template.to_s
      raise ArgumentError, "template cannot be empty" if name.strip.empty?

      base = File.expand_path(name, root.to_s)
      check_inside_root!(base, root) unless absolute?(name)

      found = candidates(base).find { |candidate| File.file?(candidate) }
      raise Error, "Typst template not found: #{name} (looked for #{candidates(base).join(", ")})" unless found

      found
    end

    # The root relative template names resolve against: `app/views` under
    # Rails.root when Rails is loaded, otherwise the current directory.
    #
    # @return [String]
    def default_root
      if FrameworkDetection.rails? && ::Rails.respond_to?(:root) && ::Rails.root
        File.join(::Rails.root.to_s, "app", "views")
      else
        Dir.pwd
      end
    end

    # @api private
    def candidates(base)
      return [base] if File.extname(base) == EXTENSION

      ["#{base}#{EXTENSION}", "#{base}.pdf#{EXTENSION}"]
    end

    # @api private
    def absolute?(name)
      Pathname.new(name).absolute?
    end

    # @api private
    def check_inside_root!(path, root)
      root_path = File.expand_path(root.to_s)
      return if path.start_with?(File.join(root_path, ""))

      raise ArgumentError, "Typst template #{path} is outside the template root #{root_path}"
    end
  end
end
