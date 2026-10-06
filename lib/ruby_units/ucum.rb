# frozen_string_literal: true

require_relative "ucum/error"
require_relative "ucum/code_tables"
require_relative "ucum/nodes"
require_relative "ucum/parser"
require_relative "ucum/expression"
require_relative "ucum/serializer"

module RubyUnits
  # Strict, case-sensitive entry point for UCUM (Unified Code for Units of
  # Measure) strings. Unlike {RubyUnits::Unit.new}, which intentionally parses
  # human-friendly strings leniently, methods in this module require formal
  # UCUM codes and reject ambiguous input.
  #
  # Supported in this initial subset:
  # * proportional units with multiplication and division (m/s)
  # * decimal (metric) prefixes (km, cm, 10^3.m)
  # * integer exponents (m2, s-2)
  # * parentheses and square-bracket grouping ((m/s)2)
  # * annotations ({patient})
  # * non-proportional conversion for Celsius (Cel)
  #
  # @example
  #   RubyUnits::Ucum.parse("m/s2").unit
  #   RubyUnits::Ucum.dump(RubyUnits::Unit.new("1 km/s")) #=> "km/s"
  module Ucum
    # Parse a UCUM code into an {Expression}.
    #
    # @param source [String] formal UCUM code
    # @return [Expression]
    # @raise [ParseError] for malformed or unknown codes
    # @raise [OffsetUnitError] when an affine unit is combined illegally
    # @raise [UnsupportedSpecialError] for unimplemented special functions
    def self.parse(source)
      Expression.parse(source)
    end

    # Parse a UCUM code and attach a measured value.
    #
    # @param source [String] formal UCUM code
    # @param scalar [Numeric] measured value on the UCUM scale
    # @return [RubyUnits::Unit]
    def self.load(source, scalar = 1)
      Expression.parse(source).to_unit(scalar)
    end

    # Serialize a Unit back into a canonical UCUM code.
    #
    # @param unit [RubyUnits::Unit]
    # @return [String]
    # @raise [OutputError] when the Unit cannot be represented in UCUM
    def self.dump(unit)
      Serializer.dump(unit)
    end
  end
end
