# frozen_string_literal: true

module RubyUnits
  module Ucum
    # Case-sensitive tables describing the subset of UCUM codes understood by
    # this entry point. Keys are UCUM codes (matching must always be exact and
    # case sensitive); values are the canonical +RubyUnits::Unit+ definition
    # names (without angle brackets).
    module CodeTables
      # UCUM decimal (metric) prefix codes mapped to their scalar factor.
      # Binary prefixes are intentionally omitted.
      SI_PREFIXES = {
        "Y" => 10**24,
        "Z" => 10**21,
        "E" => 10**18,
        "P" => 10**15,
        "T" => 10**12,
        "G" => 10**9,
        "M" => 10**6,
        "k" => 10**3,
        "h" => 10**2,
        "da" => 10**1,
        "d" => 10**-1,
        "c" => 10**-2,
        "m" => 10**-3,
        "u" => 10**-6,
        "n" => 10**-9,
        "p" => 10**-12,
        "f" => 10**-15,
        "a" => 10**-18,
        "z" => 10**-21,
        "y" => 10**-24
      }.freeze

      # Proportional UCUM units mapped to canonical ruby-units definitions.
      LINEAR_UNITS = {
        # SI base units
        "m" => "meter",
        "s" => "second",
        "g" => "gram",
        "A" => "ampere",
        "K" => "tempK",
        "mol" => "mole",
        "cd" => "candela",
        "rad" => "radian",
        # SI derived units with special names
        "Hz" => "hertz",
        "N" => "newton",
        "Pa" => "pascal",
        "J" => "joule",
        "W" => "watt",
        "V" => "volt",
        "F" => "farad",
        "C" => "coulomb",
        "S" => "siemens",
        "Wb" => "weber",
        "T" => "tesla",
        "H" => "henry",
        "lm" => "lumen",
        "lx" => "lux",
        "Bq" => "becquerel",
        "Gy" => "gray",
        "Sv" => "sievert",
        "kat" => "katal",
        # angles
        "deg" => "degree",
        "gon" => "gon",
        # time
        "min" => "minute",
        "h" => "hour",
        "d" => "day",
        "a" => "year",
        "wk" => "week",
        # volume and mass
        "l" => "liter",
        "L" => "liter",
        "t" => "metric-ton",
        "u" => "AMU",
        # customary units included in UCUM
        "in" => "inch",
        "ft" => "foot",
        "yd" => "yard",
        "mi" => "mile",
        "lb" => "pound",
        "oz" => "ounce",
        "gal" => "gallon",
        "cal" => "calorie"
      }.freeze

      # Affine units (non-proportional scales with an offset). The factor is
      # applied first and +offset+ is then added to obtain the reference scale.
      # +Cel+ maps to the Kelvin scale with an offset of 273.15.
      AFFINE_UNITS = {
        "Cel" => { unit: "tempC", factor: 1, offset: 273.15 }
      }.freeze

      # Bare UCUM codes backed by a non-proportional special function.
      SPECIAL_FUNCTIONS = {
        "B" => "logbase10",
        "Np" => "ln"
      }.freeze

      # Square-bracket UCUM codes backed by a non-proportional special
      # function. These codes are recognized specifically so the unsupported
      # function can be reported with its source position.
      BRACKET_SPECIAL_FUNCTIONS = {
        "[pct]" => "logbase1024",
        "[carat]" => "logbase1905",
        "[pH]" => "ph",
        "[Np]" => "ln",
        "[B]" => "logbase10",
        "[b]" => "logbase2",
        "[lnGa]" => "ln2pi",
        "[lnBr]" => "ln10",
        "[ln10]" => "ln10",
        "[dB]" => "log100000",
        "[dBm]" => "logmilli",
        "[degF]" => "fdeg",
        "[degRe]" => "rdeg",
        "[sin]" => "sin",
        "[cos]" => "cos",
        "[tan]" => "tan"
      }.freeze

      # Numeric-only atoms that are not expressed through a ruby-units
      # definition. +%+ is the UCUM percent symbol.
      NUMERIC_UNITS = {
        "%" => Rational(1, 100),
        "[pi]" => ::Math::PI
      }.freeze

      # Reverse lookup of ruby-units definition names to UCUM codes.
      UNIT_CODES = LINEAR_UNITS.reject { |code, _| code == "L" }.invert.merge(
        {
          "liter" => "l",
          "tempC" => "Cel"
        }
      ).freeze

      # Prefix definition names used by ruby-units mapped to UCUM codes.
      PREFIX_CODES = {
        "yotta" => "Y",
        "zetta" => "Z",
        "exa" => "E",
        "peta" => "P",
        "tera" => "T",
        "giga" => "G",
        "mega" => "M",
        "kilo" => "k",
        "hecto" => "h",
        "deca" => "da",
        "deci" => "d",
        "centi" => "c",
        "milli" => "m",
        "micro" => "u",
        "nano" => "n",
        "pico" => "p",
        "femto" => "f",
        "atto" => "a",
        "zepto" => "z",
        "yocto" => "y"
      }.freeze

      # Resolve a case-sensitive simple unit code into an atom descriptor.
      #
      # @param code [String]
      # @return [Hash{Symbol => Object}]
      def self.resolve(code)
        linear = LINEAR_UNITS[code]
        if linear
          { type: :linear, unit: linear, factor: 1 }
        elsif AFFINE_UNITS.key?(code)
          AFFINE_UNITS[code].merge(type: :affine)
        elsif (numeric = NUMERIC_UNITS[code])
          { type: :numeric, factor: numeric }
        elsif (function = SPECIAL_FUNCTIONS[code])
          { type: :special, function: function }
        else
          prefixed_linear(code)
        end
      end

      # Attempt to split a code into the longest decimal prefix and a unit.
      #
      # @param code [String]
      # @return [Hash{Symbol => Object}, nil]
      def self.prefixed_linear(code)
        SI_PREFIXES.keys.sort_by(&:length).reverse.each do |prefix|
          next unless code.start_with?(prefix)

          unit_code = code[prefix.length..]
          unit = LINEAR_UNITS[unit_code]
          next unless unit

          return { type: :linear, unit: unit, prefix: prefix }
        end
        nil
      end
    end
  end
end
