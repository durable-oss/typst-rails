# frozen_string_literal: true

require "tempfile"
require "json"
require "typst_rails/helpers"
require "typst_rails/backends"

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

    # Holds the filesystem paths used during a single compilation run.
    TempPaths = Struct.new(:typ_file, :dir, :data_file_path)

    # MARK: - Attributes

    # @return [String] The Typst template source code
    attr_reader :source

    # @return [Object, nil] The view context providing access to helpers and instance variables
    attr_reader :view_context

    # MARK: - Initialization

    # Initializes the renderer with the Typst template source.
    #
    # @param source [String] The Typst template source code
    # @return [Renderer] A new renderer instance
    # @raise [ArgumentError] if source is nil
    # @raise [ArgumentError] if source is too large (exceeds MAX_SOURCE_SIZE)
    #
    # @example
    #   renderer = Renderer.new("= Hello, Typst!")
    def initialize(source)
      raise ArgumentError, "Source cannot be nil" if source.nil?

      @source = source.to_s

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
    # @raise [TypstRails::Error] if Typst compilation fails
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

      compile_typst_source(@source, data_for_typst)
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
    # @return [String] Binary PDF data
    # @raise [ArgumentError] if typst_source is empty or data is not a Hash
    # @raise [TypstRails::Error] if compilation fails or produces no output
    #
    # @note This method ensures all temporary files are cleaned up even if errors occur
    def compile_typst_source(typst_source, data = {})
      raise ArgumentError, "typst_source cannot be empty" if typst_source.nil? || typst_source.empty?
      raise ArgumentError, "data must be a Hash" unless data.is_a?(Hash)

      paths = TempPaths.new
      begin
        write_typst_source_file(paths, typst_source)
        write_typst_data_file(paths, data)
        run_typst_compiler(paths)
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
      # Create temp file in a directory that Typst can access.
      # Ensure it's in binary mode for writing source if it contains non-ASCII.
      paths.typ_file = Tempfile.new(["durable_typst_template_", ".typ"], binmode: true)
      paths.dir = File.dirname(paths.typ_file.path)

      paths.typ_file.write(typst_source)
      paths.typ_file.flush # Ensure content is written before Typst reads it.
      paths.typ_file.close # Close it so Typst can open it, especially important on Windows.
    end

    def write_typst_data_file(paths, data)
      return if data.nil? || data.empty?

      # Create a temporary JSON data file in the same directory as the Typst source.
      # The Typst template would then use `json("typst_data.json")` to load this data.
      paths.data_file_path = File.join(paths.dir, "typst_data.json")
      File.write(paths.data_file_path, data.to_json)
    rescue JSON::GeneratorError => e
      raise Error, "Failed to serialize data to JSON: #{e.message}"
    rescue StandardError => e
      raise Error, "Failed to write data file: #{e.message}"
    end

    def run_typst_compiler(paths)
      backend = Backends::Registry.resolve(configured_backend)
      backend.compile(paths.typ_file.path, paths.dir)
    rescue Error => e
      log_error(e.message)
      raise
    end

    # @return [Symbol, Backends::Base, nil] the backend preference from
    #   TypstRails.configuration, or nil if the top-level TypstRails module
    #   (and its Configuration) hasn't been loaded (e.g. when only
    #   `typst_rails/renderer` is required directly).
    def configured_backend
      return nil unless TypstRails.respond_to?(:configuration)

      TypstRails.configuration&.backend
    end

    def cleanup_temp_paths(paths)
      # Clean up all temporary files, suppressing any errors during cleanup
      rescue_cleanup_errors("temp Typst file") do
        paths.typ_file.unlink if paths.typ_file&.path && File.exist?(paths.typ_file.path)
      end
      rescue_cleanup_errors("temp data file") { safe_unlink(paths.data_file_path) }
    end

    def safe_unlink(path)
      File.unlink(path) if path && File.exist?(path)
    end

    def rescue_cleanup_errors(description)
      yield
    rescue StandardError => e
      warn "Failed to clean up #{description}: #{e.message}"
    end

    # Collects data from view_context (instance variables) and local_assigns.
    #
    # This method extracts instance variables from the view context (if available via
    # `assigns`) and merges them with local variables. The result is a hash suitable
    # for JSON serialization and injection into Typst templates.
    #
    # @param view_context [Object] The view context (typically from Rails/Sinatra)
    # @param local_assigns [Hash] Local variables passed to the template
    # @return [Hash] A hash of data suitable for JSON serialization, with symbolized keys
    # @raise [ArgumentError] if local_assigns is not a Hash
    # @raise [TypstRails::Error] if data collection fails
    #
    # @note Instance variables from view_context take precedence over local_assigns
    # @note All values are transformed for JSON serialization (dates to ISO8601, etc.)
    def collect_data_for_typst(view_context, local_assigns)
      raise ArgumentError, "local_assigns must be a Hash" unless local_assigns.is_a?(Hash)

      data = {}

      # Instance variables from the controller are available in view_context.assigns.
      if view_context.respond_to?(:assigns)
        assigns = view_context.assigns
        if assigns.is_a?(Hash)
          assigns.each do |key, value|
            data[key.to_sym] = value # Convert keys to symbols for consistency.
          end
        end
      end

      # Local assigns (e.g., from `render locals: {...}`) merge in, taking precedence.
      data.merge!(local_assigns.symbolize_keys)

      # Transform values to ensure they are JSON-serializable.
      data.transform_values do |value|
        transform_value_for_json_serialization(value)
      end
    rescue ArgumentError
      raise
    rescue StandardError => e
      raise Error, "Failed to collect data for Typst template: #{e.message}"
    end

    # Transforms various Ruby objects into JSON-friendly representations.
    #
    # This method recursively transforms Ruby objects to ensure they can be
    # serialized to JSON for Typst template consumption. It handles:
    # - ActiveRecord objects (via as_json)
    # - Date/Time objects (to ISO8601 strings)
    # - Arrays (recursively transform elements)
    # - Hashes (recursively transform values)
    #
    # @param value [Object] The value to transform
    # @return [Object] A JSON-friendly representation of the value
    #
    # @example Transforming a date
    #   transform_value_for_json_serialization(Date.today)
    #   # => "2024-01-15"
    #
    # @example Transforming an array
    #   transform_value_for_json_serialization([Date.today, "text"])
    #   # => ["2024-01-15", "text"]
    def transform_value_for_json_serialization(value)
      if active_record_value?(value)
        value.as_json # Use Rails' built-in JSON serialization for ActiveRecord objects.
      elsif value.is_a?(Date) || value.is_a?(Time) || value.is_a?(DateTime)
        value.iso8601 # Convert date/time objects to ISO8601 strings.
      elsif value.is_a?(Array)
        value.map { |v| transform_value_for_json_serialization(v) } # Recursively transform array elements.
      elsif value.is_a?(Hash)
        # Recursively transform hash values.
        value.transform_values do |v_hash|
          transform_value_for_json_serialization(v_hash)
        end
      else
        value # Return other types as-is, assuming they are JSON-serializable.
      end
    end

    # @return [Boolean] whether +value+ is an ActiveRecord model or relation
    def active_record_value?(value)
      return false unless defined?(::ActiveRecord::Base)

      value.is_a?(::ActiveRecord::Base) ||
        (defined?(::ActiveRecord::Relation) && value.is_a?(::ActiveRecord::Relation))
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
    def method_missing(method_name, *args, &block)
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

  # Error class for Typst-related errors.
  #
  # Raised when Typst compilation fails, when files cannot be created,
  # or when other Typst-specific errors occur during rendering.
  #
  # @example Handling Typst errors
  #   begin
  #     renderer.render(nil, data)
  #   rescue TypstRails::Error => e
  #     Rails.logger.error "Typst compilation failed: #{e.message}"
  #     render plain: "PDF generation failed", status: 500
  #   end
  class Error < StandardError; end
end
