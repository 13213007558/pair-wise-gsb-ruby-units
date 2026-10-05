# frozen_string_literal: true

module RubyUnits
  # Perform Buckingham Pi dimensional analysis on a collection of measured quantities.
  class BuckinghamPi
    # A dimensionless product returned by {BuckinghamPi.analyze}.
    PiGroup = Struct.new(:name, :exponents, :variables, keyword_init: true) do
      # Return the exponent applied to one input variable.
      # @param variable_index [Integer]
      # @return [Rational]
      def exponent(variable_index)
        exponents.fetch(variable_index)
      end

      # Evaluate the dimensionless product using the supplied variable values.
      # @return [RubyUnits::Unit]
      def product
        @product ||= begin
          scalar = variables.each_with_index.reduce(1) do |result, (variable, index)|
            result * BuckinghamPi.rational_power(variable.to_base.base_scalar, exponents.fetch(index))
          end
          variables.first.to_unit.unit_class.new(scalar)
        end
      end

      alias value product
      alias to_unit product
    end

    # The complete result of a Buckingham Pi analysis.
    Result = Struct.new(:variables, :dimension_matrix, :rank, :repeating_indices, :groups, keyword_init: true) do
      # @return [Array<RubyUnits::Unit>]
      def repeating_variables
        variables.values_at(*repeating_indices)
      end

      # @return [Array<Integer>]
      def non_repeating_indices
        variables.each_index.to_a - repeating_indices
      end
    end

    # Analyze one or more quantities with units.
    #
    # @param variables [Array<#to_unit>] measured quantities
    # @param repeating [Array<Integer>, nil] zero-based indices of repeated variables
    # @return [BuckinghamPi.Result]
    # @raise [ArgumentError] when the inputs or requested repeated variables are invalid
    def self.analyze(variables, repeating: nil)
      units = coerce_variables(variables)
      vectors = units.map { |unit| dimension_vector(unit) }
      matrix = build_dimension_matrix(vectors)
      pivot_columns = RationalMatrix.reduced_row_echelon_form(matrix).last
      rank = pivot_columns.size
      repeating_indices = validate_repeating_indices(repeating, units.size, rank, matrix)
      groups = build_groups(units, matrix, rank, repeating_indices)

      Result.new(
        variables: units,
        dimension_matrix: matrix,
        rank: rank,
        repeating_indices: repeating_indices,
        groups: groups
      )
    end

    # Raise a numeric base to a Rational exponent. Integer and Rational rank calculations never use
    # floating point; this helper also preserves exact Rational values when a rational root is exact.
    # @param base [Numeric]
    # @param exponent [Rational]
    # @return [Numeric]
    def self.rational_power(base, exponent)
      return base**exponent if exponent.integer?

      exact_rational_power(base, exponent) || base**exponent
    end

    def self.exact_rational_power(base, exponent)
      return nil unless base.is_a?(Integer) || base.is_a?(Rational)

      value = base.to_r
      degree = exponent.denominator
      return nil if value.negative? && degree.even?

      numerator_root = integer_root(value.numerator.abs, degree)
      denominator_root = integer_root(value.denominator.abs, degree)
      return nil unless numerator_root && denominator_root

      sign = value.negative? && degree.odd? ? -1 : 1
      Rational(sign * numerator_root, denominator_root)**exponent.numerator
    end
    private_class_method :exact_rational_power

    def self.integer_root(value, degree)
      return 0 if value.zero?

      candidate = (0..value + 1).bsearch { |number| number**degree >= value }
      candidate if candidate && candidate**degree == value
    end
    private_class_method :integer_root

    def self.coerce_variables(variables)
      raise ArgumentError, "At least one variable is required" if variables.empty?

      variables.map.with_index do |variable, index|
        unless variable.respond_to?(:to_unit)
          raise ArgumentError, "Variable at index #{index} must respond to #to_unit"
        end

        unit = variable.to_unit
        unless unit.is_a?(RubyUnits::Unit)
          raise ArgumentError, "Variable at index #{index} must convert to a RubyUnits::Unit"
        end

        unit
      end
    end
    private_class_method :coerce_variables

    def self.dimension_vector(unit)
      base_unit = unit.to_base
      unit_class = base_unit.unit_class
      vector = ::Array.new(unit_class::SIGNATURE_VECTOR.size, 0)

      apply_dimension_tokens(vector, base_unit.numerator, 1, unit_class)
      apply_dimension_tokens(vector, base_unit.denominator, -1, unit_class)
      vector
    end
    private_class_method :dimension_vector

    def self.apply_dimension_tokens(vector, tokens, sign, unit_class)
      tokens.each do |token|
        next if token == RubyUnits::Unit::UNITY_ARRAY.first

        definition = unit_class.definition(token)
        dimension_index = unit_class::SIGNATURE_VECTOR.index(definition&.kind)
        vector[dimension_index] += sign if dimension_index
      end
    end
    private_class_method :apply_dimension_tokens

    def self.build_dimension_matrix(vectors)
      row_count = vectors.first.size
      row_count.times.filter_map do |row_index|
        row = vectors.map { |vector| vector.fetch(row_index) }
        row unless row.all?(&:zero?)
      end
    end
    private_class_method :build_dimension_matrix

    def self.validate_repeating_indices(repeating, variable_count, rank, matrix)
      return default_repeating_indices(matrix) if repeating.nil?

      unless repeating.is_a?(::Array) && repeating.all?(Integer)
        raise ArgumentError, "Repeated variables must be supplied as an Array of Integer indices"
      end

      if repeating.uniq.size != repeating.size || repeating.any? { |index| index.negative? || index >= variable_count }
        raise ArgumentError, "Repeated variable indices must be unique and within 0...#{variable_count}"
      end

      if repeating.size != rank
        raise ArgumentError, "#{rank} dimensionally independent repeated variables are required, but #{repeating.size} were supplied"
      end

      selected_matrix = matrix.map { |row| repeating.map { |index| row.fetch(index) } }
      selected_rank = RationalMatrix.rank(selected_matrix)
      return repeating if selected_rank == rank

      raise ArgumentError, "Repeated variables at indices #{repeating.inspect} are dimensionally dependent: their rank is #{selected_rank}, but #{rank} independent variables are required"
    end
    private_class_method :validate_repeating_indices

    def self.default_repeating_indices(matrix)
      RationalMatrix.reduced_row_echelon_form(matrix).last
    end
    private_class_method :default_repeating_indices

    def self.build_groups(units, matrix, rank, repeating_indices)
      non_repeating_indices = units.each_index.to_a - repeating_indices
      selected_matrix = matrix.map { |row| repeating_indices.map { |index| row.fetch(index) } }
      independent_rows = RationalMatrix.independent_row_indices(selected_matrix, rank)
      equation_matrix = selected_matrix.values_at(*independent_rows)

      non_repeating_indices.map.with_index(1) do |free_index, group_number|
        target = independent_rows.map { |row_index| -matrix.fetch(row_index).fetch(free_index) }
        repeated_exponents = RationalMatrix.solve(equation_matrix, target, rank)
        exponents = ::Array.new(units.size, Rational(0, 1))
        repeating_indices.each_with_index { |index, position| exponents[index] = repeated_exponents.fetch(position) }
        exponents[free_index] = Rational(1, 1)

        PiGroup.new(
          name: "pi_#{group_number}",
          exponents: exponents,
          variables: units
        )
      end
    end
    private_class_method :build_groups
  end
end
