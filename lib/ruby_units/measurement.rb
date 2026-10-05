# frozen_string_literal: true

module RubyUnits
  # A Measurement wraps a {RubyUnits::Unit} together with the number of
  # significant figures carried by the value, so that "1.20 m" and "1.2 m"
  # are no longer treated as the same precision.
  #
  # Values that are defined exactly (conversion factors, counted quantities,
  # defined constants) can be flagged as exact. Exact values have infinitely
  # many significant figures and never limit the precision of a result.
  #
  # The internal scalar is always kept unrounded. Rounding to the propagated
  # precision happens only when the measurement is explicitly displayed with
  # {#to_s} or quantized with {#quantize}. This matters in chains of
  # calculations: converting units first and computing afterwards keeps full
  # precision, while writing down (truncating) intermediate values discards
  # information.
  #
  # @example A chain that converts units first, then computes
  #   length = RubyUnits::Measurement.new("1.15 m").convert_to("ft")
  #   (length * 2).to_s                    #=> "7.55 ft"
  #   # Truncating the intermediate value to "3.77 ft" first would give
  #   # 3.77 * 2 = "7.54 ft" -- the last digit is lost to early rounding.
  #
  # Precision propagation rules:
  # * Multiplication and division: the result has as many significant
  #   figures as the least precise operand.
  # * Addition and subtraction: the result is precise to the decimal place
  #   of the least precise operand (evaluated in a common unit).
  # * Unit conversions (including temperature scale offsets) preserve
  #   precision because conversion factors and offsets are exact.
  class Measurement
    # Sentinel used for the significant figures of exact values
    EXACT = Float::INFINITY

    # @return [RubyUnits::Unit] the underlying unit, always unrounded
    attr_reader :unit

    # @return [Integer, Float] number of significant figures (EXACT when exact)
    attr_reader :sig_figs

    class << self
      # Create a measurement whose value is an exact constant (e.g. a defined
      # conversion factor or a counted quantity). Exact measurements have
      # infinitely many significant figures.
      #
      # @param input [String, Numeric, RubyUnits::Unit]
      # @return [RubyUnits::Measurement]
      def exact(input)
        new(input, exact: true)
      end

      # Wrap a value in a Measurement. Numerics are treated as exact
      # constants, units get their significant figures inferred from their
      # scalar.
      #
      # @param value [Measurement, RubyUnits::Unit, Numeric]
      # @return [RubyUnits::Measurement]
      # @raise [ArgumentError] when the value cannot be wrapped
      def wrap(value)
        case value
        when Measurement
          value
        when Unit
          new(value)
        when Numeric
          exact(value)
        else
          raise ArgumentError, "Cannot convert #{value.class} to RubyUnits::Measurement"
        end
      end

      # Count the significant figures of a numeric literal. Rational literals
      # (e.g. "1/2") are exact. Trailing zeros count only with a decimal
      # point ("1.20" => 3, "1200" => 2).
      #
      # @param literal [String, Numeric]
      # @return [Integer, Float]
      def count_sig_figs(literal)
        text = literal.to_s.strip
        return EXACT if text.include?("/")

        number = text[/\A[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/]
        return 1 unless number

        mantissa = number.sub(/\A[+-]/, "").sub(/[eE][+-]?\d+\z/, "")
        integer_part, separator, fraction_part = mantissa.partition(".")
        digits = (integer_part + fraction_part).sub(/\A0+/, "")
        if digits.empty?
          # the value is zero; significant figures are the fractional zeros
          return separator.empty? ? 1 : fraction_part.length + 1
        end
        digits = digits.sub(/0+\z/, "") if fraction_part.empty?
        [digits.length, 1].max
      end

      # floor(log10(abs(value))) with a guard against floating point noise at
      # exact powers of ten. Zero is treated as having magnitude 10^0.
      #
      # @param value [Numeric]
      # @return [Integer]
      def log10_floor(value)
        return 0 if value.zero?

        magnitude = value.abs.to_f
        exponent = ::Math.log10(magnitude).floor
        exponent += 1 while magnitude >= 10.0**(exponent + 1)
        exponent -= 1 while magnitude < 10.0**exponent
        exponent
      end

      # Decimal places implied by a value and its significant figures
      #
      # @param value [Numeric]
      # @param sig_figs [Integer, Float]
      # @return [Integer, Float]
      def decimal_places(value, sig_figs)
        return EXACT if sig_figs == EXACT

        sig_figs - 1 - log10_floor(value)
      end

      # Significant figures implied by a value and its decimal places
      #
      # @param value [Numeric]
      # @param places [Integer, Float]
      # @return [Integer, Float]
      def sig_figs_from_decimal_places(value, places)
        return EXACT if places == EXACT

        [places + log10_floor(value) + 1, 1].max
      end

      # Format a scalar with the given number of significant figures,
      # preserving trailing zeros ("1.20", not "1.2").
      #
      # @param value [Numeric]
      # @param sig_figs [Integer]
      # @return [String]
      def format_scalar(value, sig_figs)
        decimals = sig_figs - 1 - log10_floor(value)
        if decimals.negative?
          format("%.0f", value.to_f.round(decimals))
        else
          format("%.#{decimals}f", value.to_f)
        end
      end
    end

    # Create a new Measurement.
    #
    # @example
    #   RubyUnits::Measurement.new("1.20 m")                  # 3 significant figures
    #   RubyUnits::Measurement.new("1.2 m")                   # 2 significant figures
    #   RubyUnits::Measurement.new("1.2 m", sig_figs: 3)      # explicit override
    #   RubyUnits::Measurement.new("12 in", exact: true)      # exact constant
    #
    # @param input [String, Numeric, RubyUnits::Unit] the value to measure
    # @param sig_figs [Integer, nil] explicit significant figures (inferred from input when nil)
    # @param exact [Boolean] mark the value as an exact constant
    def initialize(input, sig_figs: nil, exact: false)
      @unit = case input
              when Unit then input
              when Numeric then Unit.new(input.to_s)
              else Unit.new(input)
              end
      @sig_figs = if exact || sig_figs == EXACT
                    EXACT
                  elsif sig_figs
                    Integer(sig_figs)
                  else
                    infer_sig_figs(input)
                  end
    end

    # @return [Boolean] true when the value is an exact constant
    def exact?
      @sig_figs == EXACT
    end

    # The unrounded scalar of the underlying unit
    # @return [Numeric]
    def scalar
      unit.scalar
    end

    # @return [String] the units of the underlying unit
    def units(...)
      unit.units(...)
    end

    # @return [RubyUnits::Unit] the underlying unit
    def to_unit
      unit
    end

    # Convert to another unit. Conversion factors are exact, so ordinary
    # conversions preserve the significant figures. Temperature scale
    # conversions involve exact offsets, and those follow the addition rule:
    # the decimal places of the absolute (offset-free) value are preserved.
    #
    # @example
    #   RubyUnits::Measurement.new("1.20 tempC").convert_to("tempF").to_s #=> "34.16 tempF"
    #
    # @param target [String, RubyUnits::Unit]
    # @return [RubyUnits::Measurement]
    def convert_to(target)
      converted = unit.convert_to(target)
      new_sig_figs = if unit.temperature? && converted.temperature?
                       temperature_sig_figs(converted)
                     else
                       sig_figs
                     end
      self.class.new(converted, sig_figs: new_sig_figs)
    end

    alias to convert_to

    # Add two measurements. The result keeps the decimal places of the least
    # precise operand (compared in base units).
    #
    # @param other [Measurement, RubyUnits::Unit, Numeric]
    # @return [RubyUnits::Measurement]
    def +(other)
      other = self.class.wrap(other)
      result_unit = unit + other.unit
      places = [decimal_places_of(self), decimal_places_of(other)].min
      self.class.new(result_unit, sig_figs: self.class.sig_figs_from_decimal_places(result_unit.base_scalar, places))
    end

    # Subtract two measurements. Uses the same decimal place rule as #+.
    #
    # @param other [Measurement, RubyUnits::Unit, Numeric]
    # @return [RubyUnits::Measurement]
    def -(other)
      other = self.class.wrap(other)
      result_unit = unit - other.unit
      places = [decimal_places_of(self), decimal_places_of(other)].min
      self.class.new(result_unit, sig_figs: self.class.sig_figs_from_decimal_places(result_unit.base_scalar, places))
    end

    # Multiply two measurements. The result keeps the significant figures of
    # the least precise operand. Bare Numerics are exact constants and do not
    # limit precision.
    #
    # @param other [Measurement, RubyUnits::Unit, Numeric]
    # @return [RubyUnits::Measurement]
    def *(other)
      return self.class.new(unit * other, sig_figs:) if other.is_a?(Numeric)

      other = self.class.wrap(other)
      self.class.new(unit * other.unit, sig_figs: [sig_figs, other.sig_figs].min)
    end

    # Divide two measurements. Uses the same significant figure rule as #*.
    #
    # @param other [Measurement, RubyUnits::Unit, Numeric]
    # @return [RubyUnits::Measurement]
    # @raise [ZeroDivisionError] if other is zero
    def /(other)
      return self.class.new(unit / other, sig_figs:) if other.is_a?(Numeric)

      other = self.class.wrap(other)
      self.class.new(unit / other.unit, sig_figs: [sig_figs, other.sig_figs].min)
    end

    # Support expressions like 2 * measurement by treating the Numeric as
    # an exact constant.
    #
    # @param other [Numeric]
    # @return [Array(RubyUnits::Measurement, RubyUnits::Measurement)]
    def coerce(other)
      [self.class.exact(other), self]
    end

    # Format the measurement with its propagated precision. This is the only
    # place (along with {#quantize}) where the value is rounded.
    #
    # @param target [String, RubyUnits::Unit, nil] convert before formatting
    # @return [String]
    def to_s(target = nil)
      measurement = target ? convert_to(target) : self
      return measurement.unit.to_s if measurement.exact?

      formatted = self.class.format_scalar(measurement.scalar, measurement.sig_figs)
      units = measurement.units
      units.empty? ? formatted : "#{formatted} #{units}"
    end

    # @return [String]
    def inspect
      exact? ? "#{self} (exact)" : "#{self} (#{sig_figs} significant figures)"
    end

    # Return a new measurement whose internal scalar is actually rounded to
    # the propagated precision. Use this when a rounded value must be stored
    # or passed on; prefer keeping the unrounded measurement otherwise.
    #
    # @return [RubyUnits::Measurement]
    def quantize
      return self if exact?

      decimals = sig_figs - 1 - self.class.log10_floor(scalar)
      rounded = unit.class.new(scalar: scalar.round(decimals), numerator: unit.numerator, denominator: unit.denominator, signature: unit.signature)
      self.class.new(rounded, sig_figs:)
    end

    private

    # infer significant figures from the input when not given explicitly
    # @param input [String, Numeric, RubyUnits::Unit]
    # @return [Integer, Float]
    def infer_sig_figs(input)
      case input
      when Unit
        self.class.count_sig_figs(input.scalar)
      else
        self.class.count_sig_figs(input)
      end
    end

    # decimal places of a measurement, evaluated in base units so that
    # operands with different units are comparable
    # @param measurement [RubyUnits::Measurement]
    # @return [Integer, Float]
    def decimal_places_of(measurement)
      self.class.decimal_places(measurement.unit.base_scalar, measurement.sig_figs)
    end

    # Significant figures after a temperature scale conversion. The ratio
    # between scales and the scale offsets are exact constants, so the
    # decimal places of the absolute (kelvin) value are preserved.
    #
    # @param converted [RubyUnits::Unit] the converted temperature
    # @return [Integer, Float]
    def temperature_sig_figs(converted)
      return EXACT if exact?

      kelvin = unit.convert_to("tempK").scalar.to_f
      places_kelvin = case temperature_family(unit.units)
                      when :celsius
                        self.class.decimal_places(unit.scalar, sig_figs)
                      when :fahrenheit
                        rankine = kelvin * Unit::RATIO_9_5
                        sig_figs_rankine = self.class.sig_figs_from_decimal_places(rankine, self.class.decimal_places(unit.scalar, sig_figs))
                        self.class.decimal_places(kelvin, sig_figs_rankine)
                      end

      result = converted.scalar
      case temperature_family(converted.units)
      when :celsius
        self.class.sig_figs_from_decimal_places(result, places_kelvin)
      when :fahrenheit
        rankine = kelvin * Unit::RATIO_9_5
        sig_figs_rankine = self.class.sig_figs_from_decimal_places(kelvin, places_kelvin)
        places_rankine = self.class.decimal_places(rankine, sig_figs_rankine)
        self.class.sig_figs_from_decimal_places(result, places_rankine)
      end
    end

    # @param units [String] e.g. "tempC", "tempF"
    # @return [Symbol] :celsius for the kelvin-aligned scales, :fahrenheit otherwise
    def temperature_family(units)
      %w[tempC tempK].include?(units) ? :celsius : :fahrenheit
    end
  end
end
