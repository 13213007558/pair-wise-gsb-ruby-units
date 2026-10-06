# frozen_string_literal: true

module RubyUnits
  # Solve a small dense linear system whose coefficients carry units.
  class LinearSystem
    # Result returned by a unit-aware linear solve.
    class Result
      attr_reader :unknowns, :residuals

      def initialize(unknowns, residuals)
        @unknowns = unknowns
        @residuals = residuals
      end

      alias x unknowns
      alias r residuals

      # @return [Array(Array<RubyUnits::Unit>, Array<RubyUnits::Unit>)]
      def to_ary
        [unknowns, residuals]
      end

      alias deconstruct to_ary

      def deconstruct_keys(keys)
        to_h.slice(*keys)
      end

      def [](key)
        case key
        when 0, :unknowns, :x then unknowns
        when 1, :residuals, :r then residuals
        end
      end

      def to_h
        { unknowns: unknowns, residuals: residuals }
      end
    end

    # Raised when the coefficient matrix has no unique numerical solution.
    class SingularSystemError < StandardError; end

    # Raised when a numerically singular coefficient matrix contradicts b.
    class InconsistentSystemError < StandardError; end

    # @param coefficients [Array<Array<RubyUnits::Unit>>] matrix A
    # @param constants [Array<RubyUnits::Unit>] vector b
    # @param target_units [Array<String, RubyUnits::Unit>] units of x
    # @return [RubyUnits::LinearSystem::Result]
    def self.solve(coefficients, constants, target_units)
      new(coefficients, constants, target_units).solve
    end

    def initialize(coefficients, constants, target_units)
      @coefficients = coefficients
      @constants = constants
      @target_units = target_units
    end

    def solve
      validate_shape
      targets = validate_targets
      validate_dimensions(targets)

      normalized = normalized_matrix(targets)
      solved = gauss_jordan(normalized)
      unknowns = recover_unknowns(solved, targets)
      residuals = calculate_residuals(unknowns)

      Result.new(unknowns, residuals)
    end

    private

    attr_reader :coefficients, :constants, :target_units

    def validate_shape
      unless coefficients.is_a?(Array) && coefficients.all? { |row| row.is_a?(Array) }
        raise ArgumentError, "A must be an Array of rows"
      end
      raise ArgumentError, "A must not be empty" if coefficients.empty?
      raise ArgumentError, "b must be an Array" unless constants.is_a?(Array)
      raise ArgumentError, "target units must be an Array" unless target_units.is_a?(Array)
      raise ArgumentError, "b must have one entry per row" unless constants.length == coefficients.size
      raise ArgumentError, "target units must have one entry per column" unless target_units.length == coefficients.size
      raise ArgumentError, "A must be square" unless coefficients.all? { |row| row.length == coefficients.size }
    end

    def validate_targets
      target_units.map do |unit|
        target = unit.is_a?(Unit) ? unit : Unit.new(unit)
        unit_without_scalar(target)
      rescue ArgumentError
        raise ArgumentError, "target unit #{unit.inspect} is not a valid unit"
      end
    end

    def validate_dimensions(targets)
      errors = []

      coefficients.each_with_index do |row, row_index|
        validate_entry(constants[row_index], "b[#{row_index}]", errors)
        next unless constants[row_index].is_a?(Unit)

        row.each_with_index do |coefficient, column_index|
          validate_entry(coefficient, "A[#{row_index},#{column_index}]", errors)
          next unless coefficient.is_a?(Unit)

          expected_signature = constants[row_index].signature - targets[column_index].signature
          next if coefficient.signature == expected_signature

          errors << dimension_error(row_index, column_index, coefficient, targets[column_index], constants[row_index])
        end
      end

      raise ArgumentError, errors.join("\n") unless errors.empty?
    end

    def validate_entry(entry, label, errors)
      return if entry.is_a?(Unit)

      detail = entry.respond_to?(:zero?) && entry.zero? ? "; numeric zero carries no unit information" : ""
      errors << "#{label} must be a RubyUnits::Unit#{detail}"
    end

    def dimension_error(row_index, column_index, coefficient, target, constant)
      "A[#{row_index},#{column_index}] has units '#{coefficient.units}', x[#{column_index}] has target units " \
        "'#{target.units}', but b[#{row_index}] has units '#{constant.units}'"
    end

    def normalized_matrix(targets)
      coefficients.map.with_index do |row, row_index|
        row_unit = unit_without_scalar(constants[row_index])
        normalized_row = row.map.with_index do |coefficient, column_index|
          (coefficient * targets[column_index]).convert_to(row_unit).scalar
        end
        normalized_row << constants[row_index].convert_to(row_unit).scalar
      end
    end

    def unit_without_scalar(unit)
      Unit.new(
        scalar: 1,
        numerator: unit.numerator,
        denominator: unit.denominator,
        signature: unit.signature
      )
    end

    def gauss_jordan(matrix)
      augmented = matrix.map(&:dup)
      size = augmented.size
      pivot_row_index = 0

      size.times do |pivot_column|
        pivot_row = select_pivot_row(augmented, pivot_column, pivot_row_index)
        next unless pivot_row

        unless pivot_row == pivot_row_index
          temporary_row = augmented[pivot_row_index]
          augmented[pivot_row_index] = augmented[pivot_row]
          augmented[pivot_row] = temporary_row
        end
        pivot = augmented[pivot_row_index][pivot_column]
        augmented[pivot_row_index] = normalize_pivot_row(augmented[pivot_row_index], pivot)

        augmented.each_with_index do |row, row_index|
          next if row_index == pivot_row_index

          factor = row[pivot_column]
          pivot_row_values = augmented[pivot_row_index]
          new_row = row.each_with_index.map { |value, column_index| value - factor * pivot_row_values[column_index] }
          augmented[row_index] = new_row
        end
        pivot_row_index += 1
      end

      if augmented[pivot_row_index..].any? { |row| !row.last.zero? }
        raise InconsistentSystemError, "the linear system is inconsistent"
      end
      raise SingularSystemError, "the coefficient matrix is singular" unless pivot_row_index == size

      augmented.map(&:last)
    end

    def select_pivot_row(matrix, pivot_column, pivot_row_index)
      candidates = (pivot_row_index...matrix.size).reject { |row_index| matrix[row_index][pivot_column].zero? }
      candidates.max_by { |row_index| matrix[row_index][pivot_column].abs }
    end

    def normalize_pivot_row(row, pivot)
      row.map { |value| value.quo(pivot) }
    end

    def recover_unknowns(normalized_unknowns, targets)
      normalized_unknowns.zip(targets).map { |value, target| target * value }
    end

    def calculate_residuals(unknowns)
      constants.zip(coefficients).map do |constant, row|
        calculated = row.each_with_index.inject(nil) do |sum, (coefficient, column_index)|
          term = coefficient * unknowns[column_index]
          sum ? sum + term : term
        end

        (calculated - constant).convert_to(unit_without_scalar(constant))
      end
    end
  end

  class Unit
    def self.solve_linear_system(coefficients, constants, target_units)
      LinearSystem.solve(coefficients, constants, target_units)
    end

    class << self
      alias_method :matrix_solve, :solve_linear_system
      alias_method :solve_matrix, :solve_linear_system
    end
  end
end
