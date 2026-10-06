# frozen_string_literal: true

module RubyUnits
  module Ucum
    # Base class for all errors raised while working with UCUM strings.
    #
    # UCUM parsing is intentionally stricter than the permissive Unit string
    # parser. Every error carries the 0-based position of the offending source
    # code so callers processing machine-readable reports can point at the
    # exact location that could not be handled.
    class Error < StandardError
      # @return [Integer] 0-based offset into the source string
      attr_reader :position

      # @return [String] original UCUM source string
      attr_reader :source

      # @param message [String]
      # @param source [String]
      # @param position [Integer]
      def initialize(message, source, position)
        @source = source
        @position = position
        super("#{message} at position #{position} in '#{source}'")
      end
    end

    # Raised when a UCUM string is syntactically invalid or uses an unknown
    # case-sensitive unit or prefix code.
    class ParseError < Error; end

    # Raised when an affine (offset) unit such as +Cel+ is combined with
    # another unit, raised to a power other than one, or divided.
    class OffsetUnitError < Error; end

    # Raised when the source uses one of UCUM's special non-proportional
    # conversion functions (for example +[pH]+) that this library does not
    # implement.
    class UnsupportedSpecialError < Error
      # @return [String] UCUM special conversion function name
      attr_reader :function

      # @param function [String]
      # @param source [String]
      # @param position [Integer]
      def initialize(function, source, position)
        @function = function
        super("UCUM special function '#{function}' is not supported", source, position)
      end
    end

    # Raised when a parsed Unit cannot be represented as a UCUM string.
    class OutputError < StandardError; end
  end
end
