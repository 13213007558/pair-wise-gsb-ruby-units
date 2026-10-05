# frozen_string_literal: true

module RubyUnits
  # Configurable mixed-radix representation for compatible units.
  class MixedRadix
    DECIMAL_NUMBER = /(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/.freeze
    private_constant :DECIMAL_NUMBER

    # @return [Array<String>] the unit label supplied for each segment
    attr_reader :labels

    # @return [Array<String>] the canonical unit name for each segment
    attr_reader :unit_names

    # @return [Array<Integer>] the carry base between adjacent segments
    attr_reader :radices

    # Create a mixed-radix representation.
    #
    # @param units [Array<String, RubyUnits::Unit>] ordered segment units
    # @param radices [Array<Integer>] carry base from one segment to the next
    # @param unit_class [Class] class used to build unit objects
    def initialize(units, radices = nil, labels: nil, unit_class: RubyUnits::Unit)
      @unit_class = unit_class
      supplied_units = Kernel.Array(units)
      raise ArgumentError, "Mixed radix representations require at least two units" if supplied_units.size < 2

      @labels = if labels
                  Kernel.Array(labels).map { |label| label.to_s.strip }
                else
                  supplied_units.map { |unit| unit.is_a?(RubyUnits::Unit) ? unit.units : unit.to_s.strip }
                end
      if @labels.any?(&:empty?)
        raise ArgumentError, "Mixed radix unit labels cannot be empty"
      end
      unless @labels.size == supplied_units.size
        raise ArgumentError, "The number of labels must match the number of units"
      end

      @unit_objects = supplied_units.map.with_index do |unit, index|
        unit.is_a?(RubyUnits::Unit) ? unit : unit_from_label(unit.to_s, @labels[index])
      end
      @unit_names = @unit_objects.map(&:units)
      @radices = Kernel.Array(radices).map { |radix| radix_value(radix) }

      validate_configuration
    end

    # Parse a mixed-radix string into a unit expressed in the first segment's units.
    #
    # @param string [String] value such as "12°59′59.999″" or "1 h 2 min 3 s"
    # @return [RubyUnits::Unit]
    def parse(string)
      text = string.to_s.strip.sub(/\A[−-]/, "-")
      negative = text.start_with?("-")
      sign = negative ? -1 : 1
      text = text.sub(/\A[+-]/, "")
      values = {}
      segment_index = nil

      while text.strip != ""
        match = next_segment(text, segment_index)
        unless match
          invalid_representation(string)
        end

        index = match[:index]
        value = parse_number_match(match[:match])
        radix = index.zero? ? nil : @radices[index - 1]
        raise ArgumentError, "Segment value must be less than #{radix}" if radix && value >= radix

        values[index] = value
        segment_index = index
        text = match[:match][:rest].to_s

        remainder = text.strip
        unless remainder.empty? || next_segment(remainder, segment_index)
          invalid_representation(string)
        end
      end

      raise ArgumentError, %("#{string}" does not contain any segments) if values.empty?

      total = @unit_names.each_index.sum do |index|
        values.fetch(index, 0).to_r / cumulative_base(index)
      end * sign

      first_unit = @unit_objects.first
      @unit_class.new(
        scalar: total,
        numerator: first_unit.numerator,
        denominator: first_unit.denominator,
        signature: first_unit.signature
      )
    end

    # Format a unit, rounding it to the supplied precision of the final segment.
    #
    # @param unit [RubyUnits::Unit] quantity to format
    # @param precision [Numeric] increment of the final segment, defaulting to 1
    # @return [String]
    def format(unit, precision = 1)
      quantity = unit.to_unit
      ensure_compatible!(quantity)

      step = Rational(precision)
      raise ArgumentError, "Precision must be positive" unless step.positive?
      unless step.numerator == 1 || step.denominator == 1
        raise ArgumentError, "Precision must be an integer or the reciprocal of an integer"
      end

      final_value = value_in_first_unit(quantity) * cumulative_base(size - 1)
      increments = (final_value / step).round
      values = segments_from_increments(increments.abs, step)
      sign = increments.negative? ? "-" : ""

      sign + values.each_with_index.map do |value, index|
        format_segment(format_number(value, index == size - 1 ? step : 1), @labels[index])
      end.join(delimiter)
    end

    alias to_s format

    # @return [Integer] number of configured segments
    def size
      @unit_objects.size
    end

    private

    def unit_from_label(unit_label, display_label)
      definition_name = @unit_class.unit_map[unit_label] || @unit_class.unit_map[display_label]
      if definition_name
        canonical_name = definition_name[1...-1]
        return @unit_class.new(canonical_name)
      end

      @unit_class.new(unit_label)
    end

    def invalid_representation(string)
      raise ArgumentError, %("#{string}" is not a valid mixed-radix representation)
    end

    def radix_value(radix)
      return radix.to_r if radix.is_a?(Numeric)

      raise ArgumentError, "Radices must be integers greater than 1"
    end

    def validate_configuration
      unless @radices.size == size - 1
        raise ArgumentError, "Expected #{size - 1} radices for #{size} units"
      end

      unless @radices.all? { |radix| radix.denominator == 1 && radix > 1 }
        raise ArgumentError, "Radices must be integers greater than 1"
      end

      @radices.map!(&:to_i)

      first_unit = @unit_objects.first
      @unit_objects.each do |unit|
        unless unit.signature == first_unit.signature
          raise ArgumentError, %(Incompatible Units ('#{@unit_objects.first}' not compatible with '#{unit}'))
        end
      end

      validate_unique_labels
    end

    def validate_unique_labels
      seen = {}
      each_label_alias do |index, label|
        normalized = label.downcase
        if seen.key?(normalized) && seen[normalized] != index
          raise ArgumentError, %(Unit label "#{label}" is ambiguous between mixed-radix segments)
        end
        seen[normalized] = index
      end
    end

    def each_label_alias
      @unit_names.each_with_index do |unit_name, index|
        definition_name = @unit_class.unit_map.fetch(unit_name, unit_name)
        aliases = [@labels[index]] + Kernel.Array(@unit_class.definition(definition_name)&.aliases)
        aliases.uniq.each do |label|
          yield(index, label)
        end
      end
    end

    def cumulative_base(index)
      @radices.first(index).reduce(1) { |product, radix| product * radix }
    end

    def next_segment(text, previous_index)
      start_index = previous_index.nil? ? 0 : previous_index + 1
      start_index.upto(size - 1).each do |index|
        match = segment_pattern(index).match(text)
        return { index: index, match: match } if match
      end
      nil
    end

    def segment_pattern(index)
      @segment_patterns ||= {}
      @segment_patterns[index] ||= begin
        label_group = aliases_for(index)
                       .map { |label| Regexp.escape(label) }
                       .sort_by(&:length)
                       .reverse
                       .join("|")
        %r{
          \A\s*[,，]?\s*
          (?:
            (?:(?<whole>#{DECIMAL_NUMBER})\s+)?(?<numerator>#{DECIMAL_NUMBER})/(?<denominator>#{DECIMAL_NUMBER})
            |
            (?<decimal>#{DECIMAL_NUMBER})
          )
          \s*(?<label>(?:#{label_group}))(?=\b|\s|\d|[,，]|\z)
          \s*(?<rest>.*)\z
        }mx
      end
    end

    def aliases_for(index)
      definition_name = @unit_class.unit_map.fetch(@unit_names[index], @unit_names[index])
      definition = @unit_class.definition(definition_name)
      ([@labels[index]] + Kernel.Array(definition&.aliases)).uniq
    end

    def parse_number_match(match)
      if match[:numerator]
        fraction = Rational(match[:numerator]) / Rational(match[:denominator])
        fraction += Rational(match[:whole]) if match[:whole]
        fraction
      else
        Rational(match[:decimal])
      end
    end

    def value_in_first_unit(unit)
      index = @unit_names.index(unit.units)
      return unit.scalar.to_r / cumulative_base(index) if index

      unit.convert_to(@unit_objects.first).scalar.to_r
    end

    def ensure_compatible!(unit)
      unless unit.compatible_with?(@unit_objects.first)
        raise ArgumentError, %(Incompatible Units ('#{unit}' not compatible with '#{@unit_objects.first}'))
      end
    end

    def segments_from_increments(increments, step)
      values = ::Array.new(size, 0)
      amount = increments * step

      (size - 1).downto(1) do |index|
        values[index] = amount % @radices[index - 1]
        amount = amount.div(@radices[index - 1])
      end
      values[0] = amount
      values
    end

    def format_number(value, step = 1)
      return finite_decimal(value, minimum_decimal_places(step)) if finite_decimal?(value)
      return value.numerator.to_s if value.denominator == 1
      "#{value.numerator}/#{value.denominator}"
    end

    def finite_decimal?(value)
      remaining = value.denominator
      [2, 5].each { |factor| remaining /= factor while (remaining % factor).zero? }
      remaining == 1
    end

    def finite_decimal(value, minimum_places = 0)
      decimal_places = [minimum_places, denominator_decimal_places(value.denominator)].max
      scaled_numerator = value.numerator * (10**decimal_places / value.denominator)
      return scaled_numerator.to_s if decimal_places.zero?

      digits = scaled_numerator.to_s.rjust(decimal_places + 1, "0")
      result = "#{digits[...-decimal_places]}.#{digits[-decimal_places..]}"
      minimum_places.zero? ? result.sub(/\.0+\z/, "") : result
    end

    def minimum_decimal_places(step)
      return 0 unless finite_decimal?(step)

      denominator_decimal_places(step.denominator)
    end

    def denominator_decimal_places(denominator)
      factors = prime_factors(denominator)
      [factors.fetch(2, 0), factors.fetch(5, 0)].max
    end

    def prime_factors(number)
      factors = Hash.new(0)
      remaining = number
      [2, 5].each do |factor|
        while (remaining % factor).zero?
          factors[factor] += 1
          remaining /= factor
        end
      end
      factors
    end

    def format_segment(number, label)
      word_label?(label) ? "#{number} #{label}" : "#{number}#{label}"
    end

    def word_label?(label)
      label.match?(/[\p{L}\p{N}_]/)
    end

    def delimiter
      @labels.each_cons(2).all? { |left, right| word_label?(left) || word_label?(right) } ? " " : ""
    end
  end
end
