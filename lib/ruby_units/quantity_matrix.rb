# frozen_string_literal: true

module RubyUnits
  # Solve small, dense linear systems whose coefficients and right-hand side have units.
  class QuantityMatrix
    # Result returned by {QuantityMatrix.solve}.
    class Solution
      # @return [Array<RubyUnits::Unit>] solved unknowns in their requested units
      attr_reader :unknowns

      # @return [Array<RubyUnits::Unit>] row residuals expressed in each row's right-hand-side unit
      attr_reader :residuals

      alias x unknowns

      def initialize(unknowns, residuals)
        @unknowns = unknowns
        @residuals = residuals
      end

      # @return [Array<RubyUnits::Unit>]
      def to_a
        unknowns
      end

      # @param index [Integer]
      # @return [RubyUnits::Unit]
      def [](index)
        unknowns[index]
      end
    end

    class Error < StandardError; end

    # Raised when a zero numeric value is supplied without a unit.
    class MissingUnitError < Error; end

    # Raised when a term in a row is dimensionally incompatible with that row.
    class IncompatibleUnitsError < Error; end

    # Raised when the dimensionless coefficient matrix has no unique solution.
    class SingularMatrixError < Error; end

    class ShapeError < ArgumentError; end

    # Solve A * x = b for a small, dense, square quantity matrix.
    #
    # Each row is scaled independently using the unit of +b[i]+, and each
    # column is scaled using the requested target unit of +x[j]+. The resulting
    # dimensionless system is solved without converting quantity scalars to
    # floats. Solved numeric values are then restored to the requested units.
    #
    # @param a [Array<Array<RubyUnits::Unit>>] square coefficient matrix
    # @param b [Array<RubyUnits::Unit>] right-hand-side vector
    # @param target_units [Array<RubyUnits::Unit, String>] requested unit for every unknown
    # @return [RubyUnits::QuantityMatrix::Solution]
    def self.solve(a, b, target_units:)
      new(a, b, target_units).solve
    end

    def initialize(a, b, target_units)
      @a = a
      @b = b
      @target_units = Array(target_units).map { |unit| unit_template(unit) }
    end

    def solve
      validate_shape
      validate_entries_have_units
      validate_dimensions

      numeric_a, numeric_b = scale_system
      values = gaussian_elimination(numeric_a, numeric_b)
      unknowns = values.each_with_index.map { |value, column| Unit.new(value, @target_units[column].units) }
      residuals = calculate_residuals(unknowns)

      Solution.new(unknowns, residuals)
    end

    private

    def unit_template(value)
      unit = case value
             when Unit
               value
             when String
               Unit.new(value)
             else
               raise ArgumentError, "target unit must be a Unit or String (got #{value.class})"
             end

      Unit.new(1, unit.units)
    end

    def validate_shape
      raise ShapeError, "A must be an Array of Arrays" unless @a.is_a?(::Array) && @a.all? { |row| row.is_a?(::Array) }
      raise ShapeError, "b must be an Array" unless @b.is_a?(::Array)
      raise ShapeError, "A must not be empty" if @a.empty?
      raise ShapeError, "A must be square" unless @a.map(&:length).uniq.one? && @a.size == @a.first.size
      raise ShapeError, "b must have #{@a.size} entries" unless @b.size == @a.size
      raise ShapeError, "target_units must have #{@a.first.size} entries" unless @target_units.size == @a.first.size
    end

    def validate_entries_have_units
      missing = []

      @a.each_with_index do |row, row_index|
        row.each_with_index do |coefficient, column_index|
          missing << "A[#{row_index}, #{column_index}] is zero but has no unit; pass a Unit such as Unit.new(0, 'N/m') instead" if bare_zero?(coefficient)
          next if coefficient.is_a?(Unit)

          raise ArgumentError, "A[#{row_index}, #{column_index}] must be a Unit (got #{coefficient.class})" unless bare_zero?(coefficient)
        end
      end

      @b.each_with_index do |value, index|
        missing << "b[#{index}] is zero but has no unit; pass a Unit such as Unit.new(0, 'N') instead" if bare_zero?(value)
        next if value.is_a?(Unit)

        raise ArgumentError, "b[#{index}] must be a Unit (got #{value.class})" unless bare_zero?(value)
      end

      raise MissingUnitError, missing.join("\n") unless missing.empty?
    end

    def bare_zero?(value)
      !value.is_a?(Unit) && value.respond_to?(:zero?) && value.zero?
    end

    def validate_dimensions
      incompatible = []

      @a.each_with_index do |row, row_index|
        row.each_with_index do |coefficient, column_index|
          expected_signature = @b[row_index].signature - @target_units[column_index].signature
          next if coefficient.signature == expected_signature

          incompatible << "row #{row_index}: #{coefficient.units.inspect} * #{@target_units[column_index].units.inspect} is incompatible with #{@b[row_index].units.inspect}"
        end
      end

      raise IncompatibleUnitsError, incompatible.join("\n") unless incompatible.empty?
    end

    def scale_system
      numeric_a = @a.map.with_index do |row, row_index|
        row_unit = Unit.new(1, @b[row_index].units)

        row.map.with_index do |coefficient, column_index|
          (coefficient * @target_units[column_index]).convert_to(row_unit).scalar.to_r
        end
      end

      numeric_b = @b.map { |value| value.convert_to(Unit.new(1, value.units)).scalar.to_r }

      [numeric_a, numeric_b]
    end

    def gaussian_elimination(source_a, source_b)
      a = source_a.map(&:dup)
      b = source_b.dup
      n = a.size

      n.times do |column|
        pivot = (column...n).max_by { |row| a[row][column].abs }
        pivot_value = a[pivot][column]
        raise SingularMatrixError, "matrix is singular; no unique solution exists" if pivot_value.zero?

        unless column == pivot
          a[column], a[pivot] = a[pivot], a[column]
          b[column], b[pivot] = b[pivot], b[column]
        end
        pivot_value = a[column][column]

        n.times { |j| a[column][j] /= pivot_value }
        b[column] /= pivot_value

        n.times do |row|
          next if row == column

          factor = a[row][column]
          next if factor.zero?

          n.times { |j| a[row][j] -= factor * a[column][j] }
          b[row] -= factor * b[column]
        end
      end

      b
    end

    def calculate_residuals(unknowns)
      @a.map.with_index do |row, row_index|
        terms = row.map.with_index { |coefficient, column| coefficient * unknowns[column] }
        row_unit = Unit.new(1, @b[row_index].units)
        (terms.inject(:+) - @b[row_index]).convert_to(row_unit)
      end
    end
  end
end
