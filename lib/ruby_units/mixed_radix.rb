# frozen_string_literal: true

module RubyUnits
  # Mixed-radix ("mixed carry") representation for quantities that are
  # conventionally written as a sequence of segments, such as angles
  # (12°59′59.999″) or durations (12:34:56.789), when the rest of the
  # system only accepts a single {RubyUnits::Unit}.
  #
  # The caller configures the unit of each segment, the carry base between
  # consecutive segments, and the separator appended to each segment when
  # formatting. Values are always handled as a whole: rounding of the last
  # segment may carry all the way up into the first segment, and a leading
  # sign applies to the entire value, so "-0°1′" round-trips as a negative
  # quantity instead of being misread as a positive one.
  #
  # @example Degrees, arcminutes, arcseconds
  #   RubyUnits::Unit.define("arcmin") do |unit|
  #     unit.definition = RubyUnits::Unit.new(Rational(1, 60), "deg")
  #     unit.aliases = %w[arcmin]
  #   end
  #   RubyUnits::Unit.define("arcsec") do |unit|
  #     unit.definition = RubyUnits::Unit.new(Rational(1, 60), "arcmin")
  #     unit.aliases = %w[arcsec]
  #   end
  #   dms = RubyUnits::MixedRadix.new(units: %w[deg arcmin arcsec],
  #                                   bases: [60, 60],
  #                                   separators: ["°", "′", "″"])
  #   angle = dms.parse("12°59′59.999″")
  #   dms.format(angle, precision: 3) # => "12°59′59.999″"
  #
  # @example Hours, minutes, seconds
  #   hms = RubyUnits::MixedRadix.new(units: %w[hour min sec],
  #                                   bases: [60, 60],
  #                                   separators: [":", ":", ""])
  #   hms.format(hms.parse("12:34:56.789"), precision: 3) # => "12:34:56.789"
  class MixedRadix
    # A segment value without a sign; a sign is only allowed in front of the
    # whole value so that it applies to every segment at once.
    SEGMENT_NUMBER = /\d+(?:\.\d+)?|\.\d+/

    # Relative tolerance used when checking that a carry base matches the
    # ratio between two consecutive segment units.
    BASE_RATIO_TOLERANCE = 1e-9

    # @return [Array<String>] unit of each segment, from largest to smallest
    attr_reader :units

    # @return [Array<Integer>] carry bases; +bases[i]+ segments of unit
    #   +units[i + 1]+ make one segment of unit +units[i]+
    attr_reader :bases

    # @return [Array<String>] separator appended after each segment
    attr_reader :separators

    # @param units [Array<String, Symbol>] unit of each segment, from largest
    #   to smallest; all units must be dimensionally compatible and each
    #   carry base must match the ratio between its neighboring units
    # @param bases [Array<Integer>] carry bases between consecutive segments,
    #   one fewer than the number of units, each greater than 1
    # @param separators [Array<String>, nil] separator appended after each
    #   segment; only the last one may be empty. Defaults to a single space
    #   between segments and nothing after the last one.
    # @raise [ArgumentError] when the segment definition is inconsistent or
    #   the units are not dimensionally compatible
    def initialize(units:, bases:, separators: nil)
      @units = Array(units).map(&:to_s).freeze
      raise ArgumentError, "at least two segment units are required" if @units.size < 2

      @bases = Array(bases).freeze
      unless @bases.size == @units.size - 1 && @bases.all? { |base| base.is_a?(Integer) && base > 1 }
        raise ArgumentError, "bases must be #{@units.size - 1} integers greater than 1"
      end

      @separators = (separators ? Array(separators).map(&:to_s) : ::Array.new(@units.size - 1, " ") + [""]).freeze
      raise ArgumentError, "separators must have one entry per segment" unless @separators.size == @units.size
      raise ArgumentError, "only the last separator may be empty" if @separators[0...-1].any?(&:empty?)

      validate_units!
    end

    # Parse a mixed-radix string into a single {RubyUnits::Unit} expressed in
    # the first (largest) segment unit. Trailing segments may be omitted and
    # default to zero. A leading + or - applies to the whole value, so
    # "-0°1′" is negative even though its first segment is zero. Segments
    # without a fractional part parse as Integers, decimal segments parse as
    # exact Rationals.
    #
    # @param string [String] e.g. "12°59′59.999″"
    # @return [RubyUnits::Unit]
    # @raise [ArgumentError] when the string does not match the configured segments
    def parse(string)
      match = parse_regex.match(string.to_s)
      raise ArgumentError, "cannot parse #{string.inspect} with segments #{units.inspect}" unless match

      captures = match.captures
      total = units.each_index.reduce(0) do |sum, index|
        text = captures[index + 1]
        text ? sum + (segment_number(text) * segment_scales[index]) : sum
      end
      total = -total if captures[0] == "-"
      RubyUnits::Unit.new(RubyUnits::Unit.normalize_to_i(total), units.first)
    end

    # Format a value as a mixed-radix string. The value is converted to the
    # first segment unit and decomposed into segments using the configured
    # carry bases. When +precision+ is given, the last segment is rounded to
    # that many decimal places; rounding may carry all the way up into the
    # first segment (12°59′59.999″ with precision 2 formats as "13°0′0.00″").
    # Negative values are handled as a whole and get a single leading sign.
    # Rational scalars keep their exact value.
    #
    # @param value [RubyUnits::Unit, Numeric] a Unit compatible with the
    #   first segment unit, or a Numeric interpreted in the first segment unit
    # @param precision [Integer, nil] decimal places for the last segment;
    #   when nil the last segment is rendered with its natural representation
    # @return [String]
    # @raise [ArgumentError] when the value is not compatible with the segment units
    def format(value, precision: nil)
      unless precision.nil? || (precision.is_a?(Integer) && !precision.negative?)
        raise ArgumentError, "precision must be a non-negative Integer or nil"
      end

      scalar = coerce_scalar(value)
      raise ArgumentError, "cannot format complex values" if scalar.is_a?(Complex)

      negative = scalar.negative?
      total = scalar.abs * last_segment_factor
      total = total.round(precision) if precision
      segments = decompose(total)
      body = segments.each_with_index.map { |segment, index| format_segment(segment, index, precision) }.join
      negative && !total.zero? ? "-#{body}" : body
    end

    private

    # number of last-segment units in one first-segment unit
    # @return [Integer]
    def last_segment_factor
      @last_segment_factor ||= bases.reduce(1, :*)
    end

    # value of one segment-i unit measured in the first segment unit
    # @return [Array<Numeric>]
    def segment_scales
      @segment_scales ||= bases.reduce([1]) { |scales, base| scales << Rational(scales.last, base) }
    end

    # @return [Regexp] matches the configured segments, trailing ones optional
    def parse_regex
      @parse_regex ||= begin
        pattern = +"([+-])?\s*"
        units.each_index do |index|
          segment = "(#{SEGMENT_NUMBER})\s*#{Regexp.escape(separators[index])}"
          pattern.concat(index.zero? ? segment : "(?:\s*#{segment}")
        end
        pattern.concat(")?" * (units.size - 1))
        /\A\s*#{pattern}\s*\z/
      end
    end

    # @param text [String]
    # @return [Integer, Rational] exact numeric value of a segment
    def segment_number(text)
      return Integer(text) unless text.include?(".")

      Rational(text.start_with?(".") ? "0#{text}" : text)
    end

    # @param value [RubyUnits::Unit, Numeric]
    # @return [Numeric] scalar of the value expressed in the first segment unit
    def coerce_scalar(value)
      unit = value.is_a?(RubyUnits::Unit) ? value : RubyUnits::Unit.new(value, units.first)
      unit.convert_to(units.first).scalar
    rescue ArgumentError
      raise ArgumentError, "#{value} is not compatible with segment unit #{units.first.inspect}"
    end

    # split a non-negative total (in last-segment units) into segment values,
    # largest segment first; only the last segment may be fractional
    # @return [Array<Numeric>]
    def decompose(total)
      segments = ::Array.new(units.size)
      remainder = total
      (units.size - 1).downto(1) do |index|
        quotient, segment = remainder.divmod(bases[index - 1])
        segments[index] = segment
        remainder = quotient
      end
      segments[0] = remainder
      segments
    end

    # @return [String] a segment value followed by its separator
    def format_segment(segment, index, precision)
      formatted = if index == units.size - 1
                    format_last_segment(segment, precision)
                  else
                    segment.to_i.to_s
                  end
      "#{formatted}#{separators[index]}"
    end

    # @return [String]
    def format_last_segment(segment, precision)
      return sprintf("%.#{precision}f", segment) if precision
      return segment.to_i.to_s if segment.is_a?(Rational) && segment.denominator == 1

      segment.to_s
    end

    # @raise [ArgumentError] when a segment unit is unknown, dimensionally
    #   incompatible with the first unit, or inconsistent with its carry base
    def validate_units!
      first = RubyUnits::Unit.new("1 #{units.first}")
      units.each do |unit|
        unless RubyUnits::Unit.new("1 #{unit}") =~ first
          raise ArgumentError, "segment unit #{unit.inspect} is not compatible with #{units.first.inspect}"
        end
      end
      bases.each_with_index do |base, index|
        ratio = RubyUnits::Unit.new("1 #{units[index]}").convert_to(units[index + 1]).scalar
        next if (ratio.to_f / base - 1).abs <= BASE_RATIO_TOLERANCE

        raise ArgumentError,
              "carry base #{base} does not match the ratio between #{units[index].inspect} and #{units[index + 1].inspect}"
      end
    end
  end
end
