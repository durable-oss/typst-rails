# frozen_string_literal: true

require "open3"
require "tempfile"
require "json"
require "typst_rails/helpers"

# Only require ActiveSupport extensions if available
begin
  require "active_support/core_ext/hash/keys" # for symbolize_keys
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

      output_pdf_path = nil
      temp_typ_file = nil
      output_temp_pdf_file = nil
      temp_data_file_path = nil

      begin
        # Create temp file in a directory that Typst can access.
        # Ensure it's in binary mode for writing source if it contains non-ASCII.
        temp_typ_file = Tempfile.new(["durable_typst_template_", ".typ"], binmode: true)
        temp_dir = File.dirname(temp_typ_file.path) # Directory for this temp file and related files.

        temp_typ_file.write(typst_source)
        temp_typ_file.flush # Ensure content is written before Typst reads it.
        temp_typ_file.close # Close it so Typst can open it, especially important on Windows.

        # Basic command structure. Configuration for executable path, font paths, etc.,
        # would be integrated here, possibly from TypstRails.configuration.
        cmd = %w[typst compile]

        # Set the root directory for the Typst compilation, allowing relative imports
        # (e.g., for the data file or other assets) from the temp directory.
        cmd << "--root" << temp_dir

        if data && !data.empty?
          # Create a temporary JSON data file in the same directory as the Typst source.
          # The Typst template would then use `json("typst_data.json")` to load this data.
          temp_data_file_path = File.join(temp_dir, "typst_data.json")
          begin
            File.write(temp_data_file_path, data.to_json)
          rescue JSON::GeneratorError => e
            raise Error, "Failed to serialize data to JSON: #{e.message}"
          rescue StandardError => e
            raise Error, "Failed to write data file: #{e.message}"
          end
        end

        # Add the path to the temporary Typst source file to the command.
        cmd << temp_typ_file.path

        # Prepare a temporary file for Typst's PDF output.
        output_temp_pdf_file = Tempfile.new(["durable_typst_output_", ".pdf"], temp_dir, binmode: true)
        output_temp_pdf_file.close # Close it so Typst can write to its path.
        output_pdf_path = output_temp_pdf_file.path
        cmd << output_pdf_path

        begin
          _stdout_str, stderr_str, status = Open3.capture3(*cmd)
        rescue Errno::ENOENT => e
          raise Error, "Typst executable not found. Please ensure Typst is installed and in your PATH. (#{e.message})"
        rescue StandardError => e
          raise Error, "Failed to execute Typst compiler: #{e.message}"
        end

        if status.success?
          unless File.exist?(output_pdf_path)
            raise Error, "Typst compilation succeeded but output file was not created"
          end

          pdf_data = File.binread(output_pdf_path)

          raise Error, "Typst compilation produced an empty PDF" if pdf_data.empty?

          pdf_data
        else
          error_message = "Typst compilation failed.\n"
          error_message += "Command: #{cmd.join(" ")}\n" # Log the command for debugging.
          error_message += "Stderr: #{stderr_str}" unless stderr_str.empty?
          log_error(error_message)
          raise Error, error_message # Raise a gem-specific error.
        end
      rescue Error
        # Re-raise our own errors
        raise
      rescue StandardError => e
        # Catch and wrap unexpected errors
        error_message = "Unexpected error during Typst compilation: #{e.class} - #{e.message}"
        log_error(error_message)
        raise Error, error_message
      ensure
        # Clean up all temporary files, suppressing any errors during cleanup
        begin
          temp_typ_file.unlink if temp_typ_file&.path && File.exist?(temp_typ_file.path)
        rescue StandardError => e
          warn "Failed to clean up temp Typst file: #{e.message}"
        end

        begin
          output_temp_pdf_file.unlink if output_temp_pdf_file&.path && File.exist?(output_temp_pdf_file.path)
        rescue StandardError => e
          warn "Failed to clean up temp PDF file: #{e.message}"
        end

        begin
          File.unlink(temp_data_file_path) if temp_data_file_path && File.exist?(temp_data_file_path)
        rescue StandardError => e
          warn "Failed to clean up temp data file: #{e.message}"
        end
      end
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
      if defined?(::ActiveRecord::Base) && (value.is_a?(::ActiveRecord::Base) || (defined?(::ActiveRecord::Relation) && value.is_a?(::ActiveRecord::Relation)))
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
