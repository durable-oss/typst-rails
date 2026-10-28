# frozen_string_literal: true

require "open3"
require "typst_rails/backends/base"

module TypstRails
  module Backends
    # Compiles Typst documents by shelling out to the `typst` CLI executable.
    #
    # This is the original TypstRails backend and remains the default when the
    # `typst` gem is not installed. It requires Typst to be installed separately
    # and available on PATH (or at {TypstRails::Configuration#typst_executable_path}).
    #
    # @example
    #   backend = TypstRails::Backends::Cli.new
    #   backend.available? #=> true, if `typst` is on PATH
    #   pdf_data = backend.compile("/tmp/doc.typ", "/tmp")
    class Cli < Base
      # @param executable_path [String, nil] path to (or name of) the Typst executable.
      #   Defaults to {TypstRails::Configuration#typst_executable_path}, falling back to "typst".
      def initialize(executable_path: nil)
        super()
        @executable_path = executable_path
      end

      # A path containing a directory separator is checked directly; a bare
      # name is looked up on PATH, as the compile command would be. No shell
      # is involved, so the path is never interpreted.
      #
      # @return [Boolean] whether the configured Typst executable can be found
      def available?
        path = executable_path
        return executable_file?(path) if directory_path?(path)

        executable_on_path?(path)
      end

      # @see Base#compile
      def compile(typ_path, root_dir)
        output_pdf_path = File.join(root_dir, "#{File.basename(typ_path, ".typ")}_output.pdf")
        cmd = [executable_path, "compile", "--root", root_dir, typ_path, output_pdf_path]

        begin
          _stdout_str, stderr_str, status = Open3.capture3(*cmd)
        rescue Errno::ENOENT => e
          raise Error, "Typst executable not found. Please ensure Typst is installed and in your PATH. (#{e.message})"
        rescue StandardError => e
          raise Error, "Failed to execute Typst compiler: #{e.message}"
        end

        raise_compilation_failure(cmd, stderr_str) unless status.success?
        read_compiled_pdf(output_pdf_path)
      ensure
        safe_unlink(output_pdf_path)
      end

      private

      # The safe-navigation operator does not help here: TypstRails.configuration
      # raises NoMethodError when the top-level TypstRails module has not been
      # loaded, which happens when "typst_rails/renderer" is required on its own.
      def executable_path
        @executable_path || configured_executable_path || "typst"
      end

      def configured_executable_path
        return nil unless TypstRails.respond_to?(:configuration)

        TypstRails.configuration&.typst_executable_path
      end

      def directory_path?(path)
        [File::SEPARATOR, File::ALT_SEPARATOR].compact.any? { |separator| path.include?(separator) }
      end

      def executable_on_path?(name)
        extensions = [""] + ENV.fetch("PATHEXT", "").split(File::PATH_SEPARATOR)

        ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
          extensions.any? { |ext| executable_file?(File.join(dir, "#{name}#{ext}")) }
        end
      end

      def executable_file?(path)
        File.file?(path) && File.executable?(path)
      end

      def read_compiled_pdf(output_pdf_path)
        raise Error, "Typst compilation succeeded but output file was not created" unless File.exist?(output_pdf_path)

        pdf_data = File.binread(output_pdf_path)
        raise Error, "Typst compilation produced an empty PDF" if pdf_data.empty?

        pdf_data
      end

      def raise_compilation_failure(cmd, stderr_str)
        error_message = "Typst compilation failed.\n"
        error_message += "Command: #{cmd.join(" ")}\n"
        error_message += "Stderr: #{stderr_str}" unless stderr_str.empty?
        raise Error, error_message
      end

      def safe_unlink(path)
        File.unlink(path) if path && File.exist?(path)
      rescue StandardError => e
        warn "TypstRails: Failed to clean up temp PDF file: #{e.message}"
      end
    end
  end
end
