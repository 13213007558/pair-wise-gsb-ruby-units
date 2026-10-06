# frozen_string_literal: true

module RubyUnits
  module Ucum
    # A parsed UCUM code bound to a concrete {RubyUnits::Unit}. The parsed
    # {Nodes::Term tree} is retained so annotations can be emitted again even
    # though the Unit representation itself does not carry them.
    class Expression
      # @return [String] original UCUM code
      attr_reader :source

      # @return [Nodes::Term]
      attr_reader :tree

      # @return [RubyUnits::Unit] unit represented by the code (scalar 1)
      attr_reader :unit

      # @param source [String]
      # @return [Expression]
      def self.parse(source)
        tree = Parser.parse(source)
        new(source: source, tree: tree, unit: Semantics.unit(source, tree))
      end

      # @param source [String]
      # @param tree [Nodes::Term]
      # @param unit [RubyUnits::Unit]
      def initialize(source:, tree:, unit:)
        @source = source
        @tree = tree
        @unit = unit
      end

      # Build a measured quantity in this unit.
      #
      # @param scalar [Numeric] measured value on the UCUM scale
      # @return [RubyUnits::Unit]
      def to_unit(scalar = 1)
        Semantics.unit(source, tree, scalar)
      end

      # Convert a value expressed in this unit into another UCUM unit.
      #
      # @param scalar [Numeric] measured value on this scale
      # @param target [String, Expression] target UCUM code
      # @return [RubyUnits::Unit]
      def convert(scalar, target)
        target_expression = target.is_a?(Expression) ? target : Expression.parse(target)
        target_unit = target_expression.unit
        to_unit(scalar).convert_to(target_unit)
      end

      # Re-emit the code, including any annotations carried by the source.
      #
      # @return [String]
      def to_ucum
        Serializer.dump_tree(tree)
      end

      # @return [String]
      def inspect
        "#<#{self.class.name} #{source.inspect}>"
      end
    end

    # Converts a parsed UCUM AST into a {RubyUnits::Unit}.
    #
    # Linear terms are accumulated as a numeric factor plus ordered
    # prefix/unit definition tokens with signed integer powers. Affine units
    # are handled separately because their offset makes multiplication,
    # division, and exponentiation invalid.
    module Semantics
      module_function

      # @param source [String]
      # @param tree [Nodes::Term]
      # @param scalar [Numeric] measured value
      # @return [RubyUnits::Unit]
      def unit(source, tree, scalar = 1)
        result = { factor: Rational(1), numerator: [], denominator: [], affine: nil }
        evaluate_term(source, tree, 1, result, true)

        affine = result[:affine]
        if affine
          RubyUnits::Unit.new(
            scalar: Rational(scalar.to_r),
            numerator: [affine],
            denominator: RubyUnits::Unit::UNITY_ARRAY
          )
        else
          RubyUnits::Unit.new(
            scalar: Rational(scalar.to_r) * result[:factor],
            numerator: wrap(result[:numerator]),
            denominator: wrap(result[:denominator])
          )
        end
      end

      # @param source [String]
      # @param term [Nodes::Term]
      # @param outer_power [Integer] signed power inherited from a parent group
      # @param result [Hash]
      # @param root [Boolean]
      # @return [void]
      def evaluate_term(source, term, outer_power, result, root)
        term.components.each_with_index do |component, index|
          is_denominator = term.denominators[index]
          local_power = is_denominator ? -component.exponent : component.exponent
          power = local_power * outer_power_sign(outer_power)
          evaluate_component(source, component, power, result, root && term.components.size == 1)
        end
      end

      # @param power [Integer]
      # @return [Integer]
      def outer_power_sign(power)
        power.negative? ? -1 : 1
      end

      # @param source [String]
      # @param component [Nodes::Component]
      # @param power [Integer] signed effective power
      # @param result [Hash]
      # @param sole [Boolean] true when this is the only component of the root term
      # @return [void]
      def evaluate_component(source, component, power, result, sole)
        base = component.base
        case base
        when ::Numeric
          result[:factor] *= Rational(base.to_r)**power
        when Nodes::Atom
          evaluate_atom(source, base, power, result, sole)
        when Nodes::Term
          subresult = { factor: Rational(1), numerator: [], denominator: [], affine: nil }
          # Grouping raises every contained component to +power+. Build the
          # group at power 1 (or -1), then replicate it |power| times.
          evaluate_term(source, base, 1, subresult, false)
          apply_group_power(result, subresult, power)
        end
      end

      # @param result [Hash]
      # @param subresult [Hash]
      # @param power [Integer]
      # @return [void]
      def apply_group_power(result, subresult, power)
        magnitude = power.abs
        powered = {
          factor: subresult[:factor]**magnitude,
          numerator: repeat(subresult[:numerator], magnitude),
          denominator: repeat(subresult[:denominator], magnitude)
        }
        powered = reciprocal(powered) if power.negative?
        combine(result, powered)
      end

      # @param items [Array]
      # @param count [Integer]
      # @return [Array]
      def repeat(items, count)
        ::Array.new(count) { items }.flatten
      end

      # @param value [Hash]
      # @return [Hash]
      def reciprocal(value)
        {
          factor: Rational(1) / value[:factor],
          numerator: value[:denominator],
          denominator: value[:numerator]
        }
      end

      # @param source [String]
      # @param atom [Nodes::Atom]
      # @param power [Integer]
      # @param result [Hash]
      # @param sole [Boolean]
      # @return [void]
      def evaluate_atom(source, atom, power, result, sole)
        descriptor = atom.descriptor
        case descriptor[:type]
        when :numeric
          result[:factor] *= Rational(descriptor[:factor].to_r)**power
        when :affine
          raise_offset_error(source, atom) unless sole && power == 1
          result[:affine] = "<#{descriptor[:unit]}>"
        else
          add_linear(descriptor, atom.prefix, power, result)
        end
      end

      # @param source [String]
      # @param atom [Nodes::Atom]
      # @return [void]
      def raise_offset_error(source, atom)
        raise OffsetUnitError.new(
          "affine unit '#{atom.code}' cannot be multiplied, divided, or exponentiated",
          source,
          atom.position
        )
      end

      # @param descriptor [Hash]
      # @param prefix [String, nil]
      # @param power [Integer]
      # @param result [Hash]
      # @return [void]
      def add_linear(descriptor, prefix, power, result)
        tokens = []
        tokens << "<#{prefix_name(prefix)}>" if prefix
        tokens << "<#{descriptor[:unit]}>"
        append_tokens(result, tokens, power)
      end

      # @param result [Hash]
      # @param subresult [Hash]
      # @return [void]
      def combine(result, subresult)
        result[:factor] *= subresult[:factor]
        result[:numerator].concat(subresult[:numerator])
        result[:denominator].concat(subresult[:denominator])
      end

      # @param result [Hash]
      # @param tokens [Array<String>]
      # @param power [Integer]
      # @return [void]
      def append_tokens(result, tokens, power)
        return if power.zero?

        bucket = power.positive? ? result[:numerator] : result[:denominator]
        power.abs.times { bucket.concat(tokens) }
      end

      # @param prefix [String] UCUM prefix code
      # @return [String] ruby-units definition name
      def prefix_name(prefix)
        CodeTables::PREFIX_CODES.invert.fetch(prefix)
      end

      # @param array [Array<String>]
      # @return [Array<String>]
      def wrap(array)
        array.empty? ? RubyUnits::Unit::UNITY_ARRAY : array
      end
    end
  end
end
