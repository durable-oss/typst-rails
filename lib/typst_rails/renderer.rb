# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"
require "typst_rails/errors"
require "typst_rails/helpers"
require "typst_rails/backends"
require "typst_rails/data_serializer"

# Only require ActiveSupport extensions if available
begin
  require "active_support/core_ext/hash/keys" # for symbolize_keys
  require "active_support/json" # for ActiveSupport::JSON, used by to_json below
  require "active_support/core_ext/object/json" # for as_json
rescue LoadError
  # ActiveSupport not available, define minimal compatibility shims
  class Hash
    unless method_defined?(:symbolize_keys)
      def symbolize_keys
        transform_keys(&:to_sym)
      end
    end
  end
end

module TypstRails
  # The Renderer class is responsible for taking Typst source code,
  # compiling it using the Typst CLI, and returning the resulting PDF data.
  # It can optionally use data passed from a view context (instance variables and locals)
  # to make them available to the Typst template, typically via a temporary JSON file.
  # This class works independently of any web framework.
  #
  # @example Basic standalone usage
  #   typst_source = "#let data = json(\"typst_data.json\")\n= #data.title"
  #   renderer = TypstRails::Renderer.new(typst_source)
  #   pdf_data = renderer.render(nil, { title: "My Document" })
  #   File.binwrite("output.pdf", pdf_data)
  #
  # @example With view context (Rails)
  #   # In a Rails controller:
  #   # @title = "Monthly Report"
  #   # render template: "reports/monthly" # Uses .typ template file
  #
  # Key features:
  # - Automatic data serialization to JSON for Typst templates
  # - Secure temporary file handling with proper cleanup
  # - Integration with view contexts for framework support
  # - Comprehensive error handling and logging
  # - Input validation and size limits for security
  class Renderer
    include Helpers

    # MARK: - Constants

    # Maximum source size (10MB) to prevent memory issues
    MAX_SOURCE_SIZE = 10 * 1024 * 1024

    # Name of the JSON file holding template data, read in Typst with
    # `json("typst_data.json")`. It is written only when the template
    # source mentions it.
    DATA_FILE_NAME = "typst_data.json"

    # Root of the key paths that serialization errors give for locals, as in
    # "locals.items[0].amount". Instance variables are named "@name" instead.
    LOCALS_PATH = "locals"

    # Holds the filesystem paths used during a single compilation run. Each
    # run gets its own directory so concurrent renders never share a
    # typst_data.json.
    TempPaths = Struct.new(:root, :dir, :typ_path, :data_file_path)

    # MARK: - Attributes

    # @return [String] The Typst template source code
    attr_reader :source

    # @return [Object, nil] The view context providing access to helpers and instance variables
    attr_reader :view_context

    # @return [String, nil] Display name of the template, used in error
    #   messages and passed to {TypstRails::Configuration#on_warning}
    attr_reader :template

    # MARK: - Initialization

    # Initializes the renderer with the Typst template source.
    #
    # @param source [String] The Typst template source code
    # @param template [String, Pathname, nil] A name for the template, such as
    #   "app/views/reports/show.pdf.typ". Error messages and warnings use it
    #   in place of the temporary file Typst actually compiles. The Rails
    #   handler and the Sinatra and Rage helpers pass it for you.
    # @return [Renderer] A new renderer instance
    # @raise [ArgumentError] if source is nil
    # @raise [ArgumentError] if source is too large (exceeds MAX_SOURCE_SIZE)
    #
    # @example
    #   renderer = Renderer.new("= Hello, Typst!")
    #
    # @example Naming the template for error messages
    #   renderer = Renderer.new(File.read(path), template: path)
    def initialize(source, template: nil)
      raise ArgumentError, "Source cannot be nil" if source.nil?

      @source = source.to_s
      @template = template&.to_s

      return unless @source.bytesize > MAX_SOURCE_SIZE

      raise ArgumentError, "Source is too large (#{@source.bytesize} bytes, max #{MAX_SOURCE_SIZE} bytes)"
    end

    # MARK: - Public Methods

    # Renders the Typst template to PDF.
    #
    # This method compiles the Typst source code to PDF, optionally injecting data
    # from a view context and local variables. The data is serialized to JSON and
    # made available to the Typst template via a temporary JSON file.
    #
    # @param view_context [Object, nil] Optional view context providing access to helpers and instance variables
    # @param local_assigns [Hash] A hash of local variables available in the template
    # @return [String] Binary string containing the PDF data
    # @raise [ArgumentError] if local_assigns is not a Hash
    # @raise [ArgumentError] if source is empty
    # @raise [TypstRails::CompileError] if Typst rejects the template
    # @raise [TypstRails::Error] if compilation fails for another reason
    #
    # @example Render with plain data
    #   renderer = Renderer.new("= #data.title")
    #   pdf = renderer.render(nil, { title: "Report" })
    #
    # @example Render with view context (Rails)
    #   renderer = Renderer.new(typst_source)
    #   pdf = renderer.render(view_context, { extra_data: "value" })
    def render(view_context = nil, local_assigns = {})
      raise ArgumentError, "local_assigns must be a Hash" unless local_assigns.is_a?(Hash)
      raise ArgumentError, "Source is empty" if @source.empty?

      @view_context = view_context

      data_for_typst = if view_context
                         collect_data_for_typst(view_context, local_assigns)
                       else
                         local_assigns
                       end

      warnings = []
      pdf = compile_typst_source(@source, data_for_typst, warnings)
      report_warnings(warnings)
      pdf
    end

    # MARK: - Private Methods

    private

    # Compiles the Typst source code to PDF, optionally injecting data.
    #
    # This method handles the complete compilation workflow:
    # 1. Creates temporary files for Typst source and data
    # 2. Writes data to JSON file for Typst template access
    # 3. Executes the Typst compiler
    # 4. Reads and returns the generated PDF
    # 5. Cleans up all temporary files
    #
    # @param typst_source [String] The Typst template source
    # @param data [Hash] Data to be made available to the Typst template via JSON
    # @param warnings [Array<Diagnostics::Diagnostic>] receives warnings
    #   reported by a successful compile
    # @return [String] Binary PDF data
    # @raise [ArgumentError] if typst_source is empty or data is not a Hash
    # @raise [TypstRails::Error] if compilation fails or produces no output
    #
    # @note This method ensures all temporary files are cleaned up even if errors occur
    def compile_typst_source(typst_source, data = {}, warnings = [])
      raise ArgumentError, "typst_source cannot be empty" if typst_source.nil? || typst_source.empty?
      raise ArgumentError, "data must be a Hash" unless data.is_a?(Hash)

      paths = TempPaths.new
      begin
        write_typst_source_file(paths, typst_source)
        write_typst_data_file(paths, data) if reads_data_file?(typst_source)
        run_typst_compiler(paths, warnings)
      rescue Error
        raise
      rescue StandardError => e
        error_message = "Unexpected error during Typst compilation: #{e.class} - #{e.message}"
        log_error(error_message)
        raise Error, error_message
      ensure
        cleanup_temp_paths(paths)
      end
    end

    def write_typst_source_file(paths, typst_source)
      # Each run gets a private directory holding the template and its data,
      # so json("typst_data.json") resolves next to the template. Typst only
      # compiles files inside its root, so with a configured root the
      # directory is created there; otherwise it doubles as the root.
      paths.root = configured_root_path
      paths.dir = make_run_dir(paths.root)
      paths.root ||= paths.dir
      paths.typ_path = File.join(paths.dir, "template.typ")
      File.binwrite(paths.typ_path, typst_source)
    end

    def make_run_dir(root)
      return Dir.mktmpdir("typst_rails_") unless root

      begin
        Dir.mktmpdir("typst_rails_", root)
      rescue SystemCallError => e
        raise Error, "Cannot create a working directory in default_root_path #{root}: #{e.message}"
      end
    end

    # Assigns can hold whole models, so they are written to disk only for
    # templates that load them.
    def reads_data_file?(typst_source)
      typst_source.include?(DATA_FILE_NAME)
    end

    # Writes +data+ to typst_data.json next to the Typst source, where the
    # template loads it with `json("typst_data.json")`.
    #
    # The data is converted with {DataSerializer} first, and every value is
    # treated as a local: anything without a faithful JSON form raises. Data
    # from {#collect_data_for_typst} is already plain, so this pass is cheap
    # there; it does the real work for renders without a view context.
    #
    # @raise [SerializationError] if a value has no faithful JSON form
    # @raise [TypstRails::Error] if the file cannot be written
    def write_typst_data_file(paths, data)
      return if data.nil? || data.empty?

      json = JSON.generate(DataSerializer.normalize(data, path: LOCALS_PATH))
      paths.data_file_path = File.join(paths.dir, DATA_FILE_NAME)
      File.write(paths.data_file_path, json)
    rescue JSON::GeneratorError => e
      raise Error, "Failed to serialize data to JSON: #{e.message}"
    rescue Error
      raise
    rescue StandardError => e
      raise Error, "Failed to write data file: #{e.message}"
    end

    # Backends may yield diagnostic output from a successful compile; the
    # warnings in it are collected here and reported once rendering is done,
    # so an on_warning handler that raises is not mistaken for a compile
    # failure.
    def run_typst_compiler(paths, warnings)
      backend = Backends::Registry.resolve(configured_backend)
      backend.compile(paths.typ_path, paths.root) do |diagnostic_text|
        warnings.concat(Diagnostics.parse(path_rewriter(paths).rewrite(diagnostic_text)).select(&:warning?))
      end
    rescue CompileError => e
      error = contextualize(e, paths)
      log_error(error.message)
      raise error
    rescue Error => e
      log_error(e.message)
      raise
    end

    # Rebuilds a backend's CompileError with the template's name in place of
    # the temporary paths. The original stays available as #cause.
    def contextualize(error, paths)
      CompileError.new(
        path_rewriter(paths).rewrite(error.typst_message),
        template: @template, command: error.command, source: @source
      )
    end

    def path_rewriter(paths)
      Diagnostics::PathRewriter.new(
        typ_path: paths.typ_path, run_dir: paths.dir, root: paths.root, template: @template
      )
    end

    def report_warnings(warnings)
      return if warnings.empty?

      handler = configured_warning_handler
      handler&.call(warnings, @template)
    end

    # @return [#call, nil] TypstRails.configuration.on_warning, or the default
    #   logger when TypstRails has not been configured
    def configured_warning_handler
      config = TypstRails.respond_to?(:configuration) ? TypstRails.configuration : nil
      return Diagnostics.method(:log_warnings) unless config

      config.on_warning
    end

    # @return [Symbol, Backends::Base, nil] the backend preference from
    #   TypstRails.configuration, or nil if the top-level TypstRails module
    #   (and its Configuration) hasn't been loaded (e.g. when only
    #   `typst_rails/renderer` is required directly).
    def configured_backend
      return nil unless TypstRails.respond_to?(:configuration)

      TypstRails.configuration&.backend
    end

    # @return [String, nil] the configured Typst root as an absolute path
    def configured_root_path
      return nil unless TypstRails.respond_to?(:configuration)

      root = TypstRails.configuration&.default_root_path
      root && File.expand_path(root.to_s)
    end

    def cleanup_temp_paths(paths)
      return unless paths.dir

      rescue_cleanup_errors("temp directory") { FileUtils.remove_entry(paths.dir) }
    end

    def rescue_cleanup_errors(description)
      yield
    rescue StandardError => e
      warn "Failed to clean up #{description}: #{e.message}"
    end

    # Collects the data for typst_data.json from the view context's instance
    # variables (its `assigns`) and +local_assigns+, which win on a name clash.
    #
    # Values are converted with {DataSerializer}, under two policies:
    #
    # - A local was passed on purpose, so one without a faithful JSON form
    #   raises {SerializationError}, naming its key path.
    # - Instance variables include incidental ones (a form object, a service,
    #   a Proc), so one without a faithful JSON form is left out, and a single
    #   warning per render lists what was left out and why.
    #
    # Assigns whose names begin with an underscore are skipped silently. Rails
    # keeps its own controller state in such variables and filters them from
    # `assigns` itself; gems that add their own (such as `@_current_ability`)
    # are skipped the same way.
    #
    # Conversion happens only when the template reads typst_data.json. For
    # other templates the merged values are returned as they are, since they
    # are never written.
    #
    # @param view_context [Object] The view context (typically from Rails/Sinatra)
    # @param local_assigns [Hash] Local variables passed to the template
    # @return [Hash{Symbol => Object}] The data, keyed by symbolized name
    # @raise [ArgumentError] if local_assigns is not a Hash
    # @raise [SerializationError] if a local has no faithful JSON form
    # @raise [TypstRails::Error] if data collection fails
    def collect_data_for_typst(view_context, local_assigns)
      raise ArgumentError, "local_assigns must be a Hash" unless local_assigns.is_a?(Hash)

      locals = local_assigns.symbolize_keys
      assigns = data_assigns(view_context).reject { |name, _| locals.key?(name) }
      return assigns.merge(locals) unless reads_data_file?(@source)

      data = normalize_assigns(assigns)
      locals.each do |name, value|
        data[name] = DataSerializer.normalize(value, path: DataSerializer.child_path(LOCALS_PATH, name))
      end
      data
    rescue ArgumentError, Error
      raise
    rescue StandardError => e
      raise Error, "Failed to collect data for Typst template: #{e.message}"
    end

    # @return [Hash{Symbol => Object}] the view context's assigns, minus
    #   underscore-prefixed internals
    def data_assigns(view_context)
      return {} unless view_context.respond_to?(:assigns)

      assigns = view_context.assigns
      return {} unless assigns.is_a?(Hash)

      assigns.each_with_object({}) do |(key, value), result|
        result[key.to_sym] = value unless key.to_s.start_with?("_")
      end
    end

    # Converts each assign, leaving out and warning about those that have no
    # faithful JSON form.
    #
    # @return [Hash{Symbol => Object}]
    def normalize_assigns(assigns)
      omitted = []
      data = assigns.each_with_object({}) do |(name, value), result|
        result[name] = DataSerializer.normalize(value, path: "@#{name}")
      rescue SerializationError => e
        omitted << "@#{name} (#{e.path} #{e.reason})"
      end
      warn_about_omitted_assigns(omitted) unless omitted.empty?
      data
    end

    def warn_about_omitted_assigns(omitted)
      log_warning("Left #{omitted.size} instance variable(s) out of #{DATA_FILE_NAME} because they are not " \
                  "JSON-serializable: #{omitted.join("; ")}. If the template needs one, pass it as a local " \
                  "in a serializable form.")
    end

    # Transforms a value into plain JSON data.
    #
    # Kept for compatibility; it delegates to {DataSerializer.normalize}. Hash
    # keys and Symbols come back as Strings, and values with no faithful JSON
    # form raise {SerializationError} rather than passing through unchanged.
    #
    # @param value [Object] The value to transform
    # @return [Object] Plain JSON data
    # @raise [SerializationError] if the value has no faithful JSON form
    #
    # @example
    #   transform_value_for_json_serialization([Date.new(2024, 1, 15), :draft])
    #   # => ["2024-01-15", "draft"]
    def transform_value_for_json_serialization(value)
      DataSerializer.normalize(value, path: "value")
    end

    # Logs a warning to Rails.logger when available, otherwise with warn.
    #
    # @param message [String] The warning, without the "TypstRails:" prefix
    # @return [void]
    def log_warning(message)
      formatted_message = "TypstRails: #{message}"
      if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
        ::Rails.logger.warn formatted_message
      else
        warn formatted_message
      end
    rescue StandardError
      warn formatted_message
    end

    # Logs an error message to the appropriate logger.
    #
    # Attempts to use Rails.logger if available, otherwise falls back to warn.
    # Handles logging failures gracefully.
    #
    # @param message [String] The error message to log
    # @return [void]
    #
    # @note Prefixes all messages with "TypstRails:" for easy identification
    # @note Never raises exceptions, even if logging fails
    def log_error(message)
      return if message.nil? || message.empty?

      formatted_message = "TypstRails: #{message}"

      begin
        if defined?(::Rails) && ::Rails.respond_to?(:logger) && ::Rails.logger
          ::Rails.logger.error formatted_message
        else
          warn formatted_message
        end
      rescue StandardError
        # Fallback to warn if logging fails
        warn formatted_message
      end
    end

    # Delegates missing methods to the view_context.
    #
    # This allows the renderer to access framework helpers from the view context
    # (e.g., Rails helpers like `link_to`, `image_tag`, etc.) when preparing data.
    #
    # @param method_name [Symbol] The name of the missing method
    # @param args [Array] Arguments to pass to the method
    # @param block [Proc] Block to pass to the method
    # @return [Object] The result of calling the method on view_context
    # @raise [NoMethodError] if neither the renderer nor view_context respond to the method
    #
    # @see #respond_to_missing?
    #
    # ruby2_keywords keeps keyword arguments intact on every supported Ruby;
    # an explicit **kwargs would pass a stray empty hash on Ruby 2.7.
    ruby2_keywords def method_missing(method_name, *args, &block)
      if @view_context.respond_to?(method_name)
        @view_context.public_send(method_name, *args, &block)
      else
        super
      end
    end

    # Complements method_missing for `respond_to?` checks.
    #
    # Ensures that `respond_to?` correctly reports whether the renderer can respond
    # to a method, either directly or via delegation to the view_context.
    #
    # @param method_name [Symbol] The name of the method to check
    # @param include_private [Boolean] Whether to include private methods in the check
    # @return [Boolean] true if the method can be responded to, false otherwise
    #
    # @see #method_missing
    def respond_to_missing?(method_name, include_private = false)
      @view_context.respond_to?(method_name, include_private) || super
    end
  end
end
