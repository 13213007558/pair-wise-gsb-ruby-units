# frozen_string_literal: true

module RubyUnits
  # Copyright 2006-2026
  # @author Kevin C. Olbrich, Ph.D.
  # @see https://github.com/olbrich/ruby-units
  #
  # A wrapper around {RubyUnits::Unit} that tracks the precision of a measured
  # value so that "1.20 m" and "1.2 m" are not treated as the same measurement.
  #
  # The number of significant figures is parsed from string input ("1.20 m"
  # carries 3 significant figures, "1.2 m" carries 2), or supplied explicitly.
  # Values flagged as exact (defined constants, conversion factors, counts)
  # carry infinite precision and never limit the precision of a result.
  #
  # The internal {RubyUnits::Unit} always keeps the unrounded value. Rounding
  # to the reported precision happens only when the measurement is explicitly
  # formatted with {#to_s} or quantized with {#quantize}.
  #
  # Precision propagates through arithmetic using the usual laboratory rules:
  #
  # * multiplication and division (and powers) keep the *fewest significant
  #   figures* of the operands
  # * addition and subtraction keep the *least precise decimal place* of the
  #   operands (compared in a common unit)
  # * linear unit conversions preserve the significant figures
  # * affine temperature-scale conversions (e.g. tempC to tempF or tempK)
  #   preserve the decimal-place precision through the scale offset, so
  #   "20.0 tempC" displays as "68.0 tempF" and "293.2 tempK"
  #
  # @example
  #   RubyUnits::Measurement.new("1.20 m").to_s                    #=> "1.20 m"
  #   RubyUnits::Measurement.new("1.20 m").to_s("cm")              #=> "120. cm"
  #   (RubyUnits::Measurement.new("1.20 m") + RubyUnits::Measurement.new("3.45 cm")).to_s #=> "1.23 m"
  #   (RubyUnits::Measurement.new("1.20 m") * RubyUnits::Measurement.new("1.2 m")).to_s   #=> "1.4 m^2"
  class Measurement
    include Comparable

    # Significant figures carried by an exact value (defined constants and
    # counts). Exact values never limit the precision of a result.
    EXACT = Float::INFINITY

    # @return [RubyUnits::Unit] the internal, unrounded value
    attr_reader :unit

    # @return [Integer, Float] the number of significant figures,
    #   or Float::INFINITY for exact values
    attr_reader :sig_figs

    class << self
      # Create a measurement flagged as an exact constant.
      # @param value [String, Numeric, RubyUnits::Unit, Measurement]
      # @return [RubyUnits::Measurement]
      def exact(value)
        new(value, exact: true)
      end

      # Count the significant figures in a numeric string.
      # Leading zeros are never significant; trailing zeros are significant
      # only when a decimal point is present ("1.20" => 3, "1200" => 2,
      # "1200." => 4, "0.0120" => 3, "1.20e3" => 3).
      # @param number_string [String]
      # @return [Integer]
      def count_sig_figs(number_string)
        mantissa = number_string.to_s
                              .sub(/\A[+-]/, "")
                              .sub(/[eE][+-]?\d+\z/, "")
        integer_part, decimal_point, fractional_part = mantissa.partition(".")
        digits = (integer_part + fractional_part).sub(/\A0+/, "")
        digits = digits.sub(/0+\z/, "") if decimal_point.empty?
        [digits.length, 1].max
      end

      # Magnitude of a single unit of the given unit object in base SI units.
      # Computed from a differential so that temperature offsets cancel out.
      # @param unit [RubyUnits::Unit]
      # @return [Float]
      def base_scale(unit)
        return 1.0 if unit.unitless?

        units = unit.units
        (Unit.new("1 #{units}").to_base.base_scalar - Unit.new("0 #{units}").to_base.base_scalar).to_f.abs
      end

      # Parse the significant figures from the numeric portion of a string.
      # Unit-only strings, rationals, and complex numbers are exact.
      # For composite formats (e.g. "6'4\"") the first quantity is used.
      # @param string [String]
      # @return [Integer, Float]
      def sig_figs_from_string(string)
        return EXACT if string.match?(Unit::RATIONAL_NUMBER) || string.match?(Unit::COMPLEX_NUMBER)

        number_string = string[Unit::SCI_NUMBER]
        return EXACT if number_string.nil?

        count_sig_figs(number_string)
      end

      # The decimal place (base-10 exponent) of the last digit written in the
      # numeric portion of a string. "0.0" => -1, "1.2e3" => 2.
      # @param string [String]
      # @return [Integer, nil] nil when the string carries no decimal number
      def exponent_from_string(string)
        number_string = string[Unit::SCI_NUMBER]
        return nil unless number_string

        mantissa, _, scientific_exponent = number_string.partition(/[eE]/)
        fractional_digits = mantissa[/\.(\d+)/, 1]
        (scientific_exponent.empty? ? 0 : scientific_exponent.to_i) - (fractional_digits ? fractional_digits.length : 0)
      end
    end

    # @param value [String, Numeric, RubyUnits::Unit, Measurement] the measured value
    # @param sig_figs [Integer, nil] override the significant figures parsed from a String value
    # @param exact [Boolean] flag the value as an exact constant (infinite significant figures)
    # @param precision [Integer, nil] explicit decimal place of the last significant
    #   digit, as a base-10 exponent (e.g. -2 means the value is known to the
    #   hundredths place). Normally derived from +sig_figs:+; mainly used to
    #   preserve the precision of zero-valued results.
    # @note Numeric and Unit inputs carry no precision information and are
    #   treated as exact unless +sig_figs:+ is given. Rational and complex
    #   string scalars (e.g. "1/2 cup") are also treated as exact.
    def initialize(value, sig_figs: nil, exact: false, precision: nil)
      @unit = value.is_a?(Measurement) ? value.unit : Unit.new(value)
      @precision_override = precision
      @sig_figs =
        if exact
          EXACT
        elsif sig_figs
          raise ArgumentError, "sig_figs must be a positive Integer" unless sig_figs.is_a?(Integer) && sig_figs.positive?

          sig_figs
        elsif value.is_a?(Measurement)
          value.sig_figs
        elsif value.is_a?(String)
          self.class.sig_figs_from_string(value)
        else
          EXACT
        end
      @precision_override ||= self.class.exponent_from_string(value) if value.is_a?(String) && @unit.scalar.zero?
    end

    # @return [Boolean] true when the value is an exact constant
    def exact?
      @sig_figs == EXACT
    end

    # The decimal place (as a base-10 exponent) of the last significant digit
    # of the current value. "1.20 m" => -2, "1.2e3 m" => 2.
    # @return [Integer, nil] nil for exact, zero, or non-real values
    def precision_exponent
      return @precision_override if @precision_override
      return nil if exact?

      scalar = @unit.scalar
      return nil if scalar.is_a?(Complex) || !scalar.is_a?(Numeric) || scalar.zero?

      floor_log10(scalar.abs.to_f) - @sig_figs + 1
    end

    # The unrounded internal value.
    # @return [RubyUnits::Unit]
    def to_unit
      @unit
    end

    # Convert to another unit. Linear conversions preserve the significant
    # figures. Conversions between absolute temperature scales (tempC, tempF,
    # tempK, tempR) are affine, so the decimal-place precision is carried
    # through the offset instead.
    # @param other [String, RubyUnits::Unit] target unit
    # @return [RubyUnits::Measurement]
    def convert_to(other)
      converted = @unit.convert_to(other)
      return self if converted.equal?(@unit)
      return self.class.new(converted, exact: true) if exact?

      exponent = precision_exponent
      return self.class.new(converted, sig_figs: @sig_figs) if exponent.nil?

      if @unit.temperature? && converted.temperature?
        uncertainty = (10.0**exponent) * (self.class.base_scale(@unit) / self.class.base_scale(converted))
        converted_exponent = floor_log10(uncertainty)
        self.class.new(converted, sig_figs: sig_figs_for(converted.scalar, converted_exponent), precision: converted_exponent)
      else
        self.class.new(converted, sig_figs: @sig_figs)
      end
    end

    alias to convert_to

    # Add another measurement. The result keeps the least precise decimal
    # place of the operands, compared in a common (base) unit.
    # @param other [Measurement, RubyUnits::Unit, String, Numeric]
    # @return [RubyUnits::Measurement]
    def +(other)
      other = coerce_measurement(other)
      additive_result(@unit + other.unit, other)
    end

    # Subtract another measurement. Precision propagates as for {#+}.
    # @param other [Measurement, RubyUnits::Unit, String, Numeric]
    # @return [RubyUnits::Measurement]
    def -(other)
      other = coerce_measurement(other)
      additive_result(@unit - other.unit, other)
    end

    # Multiply by another measurement. The result keeps the fewest
    # significant figures of the operands. Numeric operands are exact.
    # @param other [Measurement, RubyUnits::Unit, String, Numeric]
    # @return [RubyUnits::Measurement]
    def *(other)
      other = coerce_measurement(other)
      self.class.new(@unit * other.unit, sig_figs: [@sig_figs, other.sig_figs].min)
    end

    # Divide by another measurement. Precision propagates as for {#*}.
    # @param other [Measurement, RubyUnits::Unit, String, Numeric]
    # @return [RubyUnits::Measurement]
    def /(other)
      other = coerce_measurement(other)
      self.class.new(@unit / other.unit, sig_figs: [@sig_figs, other.sig_figs].min)
    end

    # Raise to a power. The exponent is treated as exact, so the significant
    # figures are preserved.
    # @param exponent [Numeric]
    # @return [RubyUnits::Measurement]
    def **(exponent)
      self.class.new(@unit**exponent, sig_figs: @sig_figs)
    end

    # @return [RubyUnits::Measurement]
    def -@
      self.class.new(-@unit, sig_figs: @sig_figs)
    end

    # @return [RubyUnits::Measurement]
    def abs
      self.class.new(@unit.abs, sig_figs: @sig_figs)
    end

    # Return a new measurement whose internal value is rounded to the
    # reported precision. This (along with {#to_s}) is the only place the
    # unrounded internal value is discarded.
    # @return [RubyUnits::Measurement]
    def quantize
      exponent = precision_exponent
      return self if exponent.nil?

      quantized = @unit.class.new(scalar: @unit.scalar.round(-exponent),
                                  numerator: @unit.numerator,
                                  denominator: @unit.denominator,
                                  signature: @unit.signature)
      self.class.new(quantized, sig_figs: @sig_figs)
    end

    # Format the measurement, rounding the scalar to the reported precision.
    # Exact values and values without a determinable precision are formatted
    # by the underlying {RubyUnits::Unit}. Significant trailing zeros before
    # the decimal point are marked with a trailing "." ("120. cm").
    # @param target [String, RubyUnits::Unit, nil] convert to this unit before formatting
    # @return [String]
    def to_s(target = nil)
      (target ? convert_to(target) : self).formatted_string
    end

    # @return [String]
    def inspect
      to_s
    end

    # Compare by value. Precision metadata is ignored for ordering.
    # @param other [Measurement, RubyUnits::Unit, String, Numeric]
    # @return [Integer, nil]
    def <=>(other)
      @unit <=> coerce_measurement(other).unit
    rescue ArgumentError
      nil
    end

    # Two measurements are equal only when both their values and their
    # reported precisions match, so "1.20 m" does not equal "1.2 m".
    # @param other [Object]
    # @return [Boolean]
    def ==(other)
      other.is_a?(Measurement) && @sig_figs == other.sig_figs && @unit == other.unit
    end

    alias eql? ==

    # @return [Integer]
    def hash
      [@unit, @sig_figs].hash
    end

    protected

    # @return [String] the measurement formatted to its reported precision
    def formatted_string
      exponent = precision_exponent
      return @unit.to_s if exponent.nil?

      rounded = @unit.scalar.round(-exponent)
      scalar_string =
        if exponent.negative?
          format("%.#{-exponent}f", rounded)
        else
          # a trailing "." marks significant trailing zeros ("120. cm")
          integer = rounded.to_i
          !integer.zero? && (integer % 10).zero? ? "#{integer}." : integer.to_s
        end
      units = @unit.units
      return scalar_string if units.empty?

      "#{scalar_string}#{RubyUnits.configuration.separator}#{units}"
    end

    # Uncertainty of this value expressed in base SI units, or nil when exact.
    # @return [Float, nil]
    def uncertainty_in_base_units
      exponent = precision_exponent
      return nil if exponent.nil?

      (10.0**exponent) * self.class.base_scale(@unit)
    end

    private

    # Derive the significant figures of a result from its scalar and the
    # decimal place (base-10 exponent) of its least significant digit.
    # @param scalar [Numeric]
    # @param exponent [Integer]
    # @return [Integer]
    def sig_figs_for(scalar, exponent)
      return 1 if scalar.is_a?(Complex) || !scalar.is_a?(Numeric) || scalar.zero?

      [floor_log10(scalar.abs.to_f) - exponent + 1, 1].max
    end

    # Shared precision propagation for {#+} and {#-}: the result keeps the
    # least precise decimal place of the operands.
    # @param result_unit [RubyUnits::Unit]
    # @param other [Measurement]
    # @return [RubyUnits::Measurement]
    def additive_result(result_unit, other)
      uncertainties = [uncertainty_in_base_units, other.uncertainty_in_base_units].compact
      return self.class.new(result_unit, exact: true) if uncertainties.empty?

      result_exponent = floor_log10(uncertainties.max / self.class.base_scale(result_unit))
      self.class.new(result_unit, sig_figs: sig_figs_for(result_unit.scalar, result_exponent), precision: result_exponent)
    end

    # floor(log10(value)) with a small tolerance for floating point noise
    # around exact powers of ten
    # @param value [Float] positive number
    # @return [Integer]
    def floor_log10(value)
      (::Math.log10(value) + 1e-9).floor
    end

    # @param other [Measurement, RubyUnits::Unit, String, Numeric]
    # @return [RubyUnits::Measurement]
    # @raise [ArgumentError] when the object cannot be coerced
    def coerce_measurement(other)
      case other
      when Measurement, Unit, String, Numeric
        self.class.new(other)
      else
        raise ArgumentError, "Cannot coerce #{other.class} into a RubyUnits::Measurement"
      end
    end

  end
end
