# frozen_string_literal: true

module RubyUnits
  class Unit
    # Perform a Buckingham Pi analysis on a set of dimensioned variables.
    #
    # The dimensional matrix is built from integer base-unit signatures and all
    # rank and null-space calculations are performed with Rational values.
    #
    # @param variables [Array<RubyUnits::Unit, Numeric, String>, Hash]
    #   Variables to analyze. Hash keys name the variables. Array positions name
    #   array variables.
    # @param repeating [Array<RubyUnits::Unit, Integer, Symbol, String>, nil]
    #   Repeating variables to use as the dimensional basis. Array variables may
    #   be referenced by object identity, value, or zero-based index; Hash
    #   variables may be referenced by key.
    # @param repeating_variables [Array<RubyUnits::Unit, Integer, Symbol, String>, nil] alias for `repeating`
    # @return [Array<Hash>]
    #   Independent dimensionless products. Each result maps the supplied
    #   variable names to Rational or Integer exponents and includes the computed
    #   dimensionless product.
    # @raise [ArgumentError] when a variable or repeating variable is invalid,
    #   or when the supplied repeating variables are dependent or do not span
    #   the dimensional space.
    def self.buckingham_pi(variables,
                           positional_repeating = nil,
                           repeating: positional_repeating,
                           repeating_variables: repeating)
      normalized_variables = normalize_buckingham_variables(variables)
      names = normalized_variables.keys
      units = normalized_variables.values
      dimensional_matrix = units.map do |unit|
        unit.to_base.dimensional_vector.map(&:to_r)
      end.transpose.freeze
      repeating_indices = normalize_repeating_indices(names, units, variables.is_a?(::Hash), repeating_variables)

      exponent_vectors = if repeating_indices
                           buckingham_vectors_with_repeating_variables(dimensional_matrix, repeating_indices)
                         else
                           null_space_vectors(dimensional_matrix)
                         end

      exponent_vectors.map do |vector|
        exponents = vector.each_with_index.to_h { |exponent, index| [names[index], simplify_pi_exponent(exponent)] }
        product = dimensionless_pi_product(units, vector)
        {
          exponents:,
          product:,
          value: product.scalar
        }
      end
    end

    class << self
      alias buckingham_pi_analysis buckingham_pi
    end

    class << self
      private

      def normalize_buckingham_variables(variables)
        case variables
        when ::Hash
          raise ArgumentError, "No variables were supplied" if variables.empty?

          variables.to_h do |name, value|
            [name, coerce_buckingham_variable(value)]
          end
        when ::Array
          raise ArgumentError, "No variables were supplied" if variables.empty?

          variables.each_with_index.to_h { |value, index| [index, coerce_buckingham_variable(value)] }
        else
          raise ArgumentError, "Variables must be supplied as an Array or Hash"
        end
      end

      def coerce_buckingham_variable(value)
        case value
        when Unit
          value
        when Numeric, String
          new(value)
        else
          raise ArgumentError, "#{value.inspect} is not a unit variable" unless value.respond_to?(:to_unit)

          value.to_unit
        end
      end

      def normalize_repeating_indices(names, units, named, repeating_variables)
        return nil if repeating_variables.nil?

        references = Kernel.Array(repeating_variables)
        indices = references.map do |reference|
          index = repeating_variable_index(names, units, named, reference)
          unless index
            raise ArgumentError, "Repeating variable #{reference.inspect} is not one of the supplied variables"
          end

          index
        end

        raise ArgumentError, "Repeating variables must not be duplicated" if indices.uniq.length != references.length

        indices
      end

      def repeating_variable_index(names, units, named, reference)
        case reference
        when Integer
          if named
            names.index(reference)
          elsif reference.between?(0, names.length - 1)
            reference
          end
        when Unit
          units.index { |unit| unit.equal?(reference) || unit == reference }
        when Symbol, String
          names.index(reference) ||
            names.index(reference.to_sym) ||
            (reference.is_a?(Symbol) ? names.index(reference.to_s) : nil)
        end
      end

      def buckingham_vectors_with_repeating_variables(matrix, repeating_indices)
        rank = matrix_rank(matrix)
        validate_repeating_variables(matrix, repeating_indices, rank)

        ordered_indices = repeating_indices + ((0...matrix.first.length).to_a - repeating_indices)
        ordered_matrix = matrix.map { |row| ordered_indices.map { |column| row[column] } }
        echelon_form, pivots = reduced_row_echelon_form(ordered_matrix)

        unless pivots == (0...rank).to_a
          repeating_rank = pivots.count { |pivot| pivot < repeating_indices.length }
          raise ArgumentError,
                "Repeating variables are dimensionally dependent: their columns have rank " \
                "#{repeating_rank}, but #{repeating_indices.length} independent repeating variables are required"
        end

        null_space_vectors(ordered_matrix, echelon_form, pivots).map do |ordered_vector|
          ::Array.new(ordered_vector.length, 0).tap do |vector|
            ordered_vector.each_with_index do |exponent, ordered_index|
              vector[ordered_indices[ordered_index]] = exponent
            end
          end
        end
      end

      def validate_repeating_variables(matrix, repeating_indices, rank)
        supplied_count = repeating_indices.length
        return if supplied_count == rank

        repeating_matrix = matrix.map { |row| repeating_indices.map { |column| row[column] } }
        repeating_rank = matrix_rank(repeating_matrix)

        if repeating_rank < supplied_count
          variables_word = supplied_count == 1 ? "variable" : "variables"
          auxiliary_word = supplied_count == 1 ? "was" : "were"
          raise ArgumentError,
                "Repeating variables are dimensionally dependent: their columns have rank " \
                "#{repeating_rank}, but #{supplied_count} independent repeating " \
                "#{variables_word} #{auxiliary_word} supplied"
        end

        return unless supplied_count < rank
        variables_word = supplied_count == 1 ? "variable" : "variables"
        auxiliary_word = supplied_count == 1 ? "was" : "were"

        raise ArgumentError,
              "Repeating variables do not span the dimensional space: the dimensional matrix " \
              "has rank #{rank}, but only #{supplied_count} repeating " \
              "#{variables_word} #{auxiliary_word} supplied"
      end

      def null_space_vectors(matrix, echelon_form = nil, pivots = nil)
        echelon_form, pivots = reduced_row_echelon_form(matrix) if echelon_form.nil? && pivots.nil?
        column_count = matrix.first.length
        free_columns = (0...column_count).to_a - pivots

        free_columns.map do |free_column|
          vector = ::Array.new(column_count, 0r)
          vector[free_column] = 1r
          pivots.each_with_index do |pivot_column, pivot_row|
            vector[pivot_column] = -echelon_form[pivot_row][free_column]
          end
          normalize_pi_vector(vector)
        end
      end

      def reduced_row_echelon_form(matrix)
        rows = matrix.map(&:dup)
        pivots = []
        pivot_row = 0

        (0...rows.first.length).each do |column|
          candidate = (pivot_row...rows.length).find { |row| !rows[row][column].zero? }
          next unless candidate

          rows[pivot_row], rows[candidate] = rows[candidate], rows[pivot_row]
          pivot_value = rows[pivot_row][column]
          rows[pivot_row] = rows[pivot_row].map { |value| value / pivot_value }

          rows.each_with_index do |row, row_index|
            next if row_index == pivot_row

            factor = row[column]
            next if factor.zero?

            rows[row_index] = row.zip(rows[pivot_row]).map { |value, pivot_row_value| value - factor * pivot_row_value }
          end

          pivots << column
          pivot_row += 1
          break if pivot_row == rows.length
        end

        [rows, pivots]
      end

      def matrix_rank(matrix)
        reduced_row_echelon_form(matrix).last.length
      end

      def normalize_pi_vector(vector)
        first_nonzero = vector.find { !_1.zero? }
        first_nonzero.negative? ? vector.map { -_1 } : vector
      end

      def simplify_pi_exponent(exponent)
        exponent.denominator == 1 ? exponent.numerator : exponent
      end

      def dimensionless_pi_product(units, exponents)
        scalar = exponents.zip(units).map do |exponent, unit|
          rational_power(unit.to_base.scalar.to_r, exponent)
        end.reduce(1, :*)

        new(scalar)
      end

      def rational_power(value, exponent)
        return value ** exponent.numerator if exponent.denominator == 1

        numerator_root = integer_root(value.numerator.abs, exponent.denominator)
        denominator_root = integer_root(value.denominator, exponent.denominator)
        return value ** exponent unless numerator_root && denominator_root

        return value ** exponent if value.negative? && exponent.denominator.even?

        base_power = Rational(numerator_root, denominator_root) ** exponent.numerator
        value.negative? && exponent.numerator.odd? ? -base_power : base_power
      end

      def integer_root(value, degree)
        return value if value <= 1

        lower_bound = 0
        upper_bound = value
        while lower_bound <= upper_bound
          middle = (lower_bound + upper_bound) / 2
          powered = middle**degree

          return middle if powered == value
          if powered < value
            lower_bound = middle + 1
          else
            upper_bound = middle - 1
          end
        end
      end
    end
  end
end
