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

      # @return [Boolean] whether the configured Typst executable can be found
      def available?
        return true if File.exist?(executable_path)

        system("which #{executable_path} > /dev/null 2>&1") == true
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

      def executable_path
        @executable_path || TypstRails.configuration&.typst_executable_path || "typst"
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
