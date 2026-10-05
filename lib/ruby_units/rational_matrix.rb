# frozen_string_literal: true

module RubyUnits
  # Internal Integer/Rational matrix helpers used by dimensional analysis.
  class RationalMatrix
    class << self
      # @return [Array(Array<Array<Rational>>, Array<Integer>)]
      def reduced_row_echelon_form(matrix)
        rows = matrix.map { |row| row.map { |value| Rational(value, 1) } }
        return [[], []] if rows.empty?

        pivot_columns = []
        pivot_row = 0

        (0...rows.first.size).each do |column|
          nonzero_row = (pivot_row...rows.size).find { |row| rows.fetch(row).fetch(column) != 0 }
          next unless nonzero_row

          rows[pivot_row], rows[nonzero_row] = rows[nonzero_row], rows[pivot_row]
          pivot = rows[pivot_row][column]
          rows[pivot_row] = rows[pivot_row].map { |value| value / pivot }
          eliminate_column(rows, pivot_row, column)

          pivot_columns << column
          pivot_row += 1
          break if pivot_row == rows.size
        end

        [rows, pivot_columns]
      end

      def rank(matrix)
        reduced_row_echelon_form(matrix).last.size
      end

      def independent_row_indices(matrix, required_rank)
        selected_rows = []
        selected_indices = []

        matrix.each_with_index do |row, index|
          candidate = selected_rows + [row]
          next unless rank(candidate) == selected_rows.size + 1

          selected_rows = candidate
          selected_indices << index
          break if selected_indices.size == required_rank
        end

        selected_indices
      end

      def solve(matrix, vector, column_count)
        augmented = matrix.map.with_index { |row, index| row + [vector.fetch(index)] }
        reduced, = reduced_row_echelon_form(augmented)
        solution = ::Array.new(column_count, Rational(0, 1))

        reduced.each do |row|
          pivot_column = row[...-1].index { |value| !value.zero? }
          solution[pivot_column] = row.last if pivot_column
        end

        solution
      end

      private

      def eliminate_column(rows, pivot_row, column)
        rows.each_index do |row_index|
          next if row_index == pivot_row

          factor = rows[row_index][column]
          rows[row_index] = rows[row_index].map.with_index do |value, index|
            value - factor * rows[pivot_row][index]
          end
        end
      end
    end
  end
end
