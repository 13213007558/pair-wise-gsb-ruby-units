# frozen_string_literal: true

require_relative "ucum/atoms"
require_relative "ucum/parser"

module RubyUnits
  # Strict entry point for the UCUM (Unified Code for Units of Measure) codes
  # commonly produced by external detection reports.
  #
  # Unlike {RubyUnits::Unit.new}, the parser here is strict and case
  # sensitive: "mm" is a millimeter, "Mm" is a megameter, and "MM" is an
  # error. The supported subset covers ordinary proportional units, decimal
  # prefixes, integer exponents, parentheses, annotations, and the affine
  # (offset) point temperatures +Cel+ and +[degF]+.
  #
  # @example
  #   expression = RubyUnits::Ucum.parse("mg/L")   #=> #<RubyUnits::Ucum::Expression ...>
  #   expression.unit                                #=> 1 mg/L
  #   RubyUnits::Ucum.dump(expression.unit)         #=> "mg/L"
  #
  # @see http://unitsofmeasure.org/ucum.html
  class Ucum
    # A parsed UCUM expression: the proportional {RubyUnits::Unit}, the AST
    # used for canonical emission, and any annotations carried on the code.
    class Expression
      # @return [RubyUnits::Unit] the value represented by the expression
      attr_reader :unit

      # @return [RubyUnits::Ucum::Parser::ExpressionNode]
      attr_reader :ast

      # @return [String] the original UCUM code
      attr_reader :code

      # @param unit [RubyUnits::Unit]
      # @param ast [RubyUnits::Ucum::Parser::ExpressionNode]
      # @param code [String]
      def initialize(unit, ast, code)
        @unit = unit
        @ast = ast
        @code = code
      end

      # @return [Boolean] true when the expression is an affine point temperature
      def affine?
        !!affine_atom
      end

      # RubyUnits name of the point-temperature unit for an affine expression.
      # @return [String, nil]
      def point_unit
        affine_atom&.entry&.dig(:point)
      end

      # Convert a numeric value expressed in this code into another UCUM code.
      #
      # Point temperatures use affine conversion (0 Cel -> 32 [degF]); every
      # other conversion is proportional.
      #
      # @param value [Numeric]
      # @param target_code [String]
      # @return [Numeric] the value in +target_code+
      def convert(value, target_code)
        target = Ucum.parse(target_code)
        if affine? || target.affine?
          unless affine? && target.affine?
            raise Ucum::ParseError.new("cannot convert between point temperature '#{code}' and proportional unit '#{target_code}'", 0)
          end

          convert_point_temperature(value, target)
        else
          source = RubyUnits::Unit.new(
            scalar: unit.scalar * value.to_r,
            numerator: unit.numerator,
            denominator: unit.denominator
          )
          source.convert_to(target.unit).scalar
        end
      end

      # Re-emit the expression as canonical UCUM code, preserving annotations.
      # @return [String]
      def to_ucum
        Ucum.emit(ast)
      end

      alias to_s to_ucum

      # @return [String]
      def inspect
        "#<#{self.class} #{to_ucum.inspect}>"
      end

      private

      # Exact affine conversion between the two supported point temperatures.
      # @param value [Numeric]
      # @param target [RubyUnits::Ucum::Expression]
      # @return [Numeric]
      def convert_point_temperature(value, target)
        rational = value.to_r
        result = case [point_unit, target.point_unit]
                 when %w[tempC tempC]
                   rational
                 when %w[tempF tempF]
                   rational
                 when %w[tempC tempF]
                   rational * Rational(9, 5) + 32
                 when %w[tempF tempC]
                   (rational - 32) * Rational(5, 9)
                 end
        RubyUnits::Unit.normalize_to_i(result)
      end

      # @return [RubyUnits::Ucum::Parser::AtomNode, nil]
      def affine_atom
        return nil unless @ast.denominator.nil? && @ast.numerator.components.size == 1

        factor = @ast.numerator.components.first.factor
        factor.is_a?(Parser::AtomNode) && factor.entry[:kind] == AFFINE ? factor : nil
      end

    end

    class << self
      # Strictly parse a UCUM unit code.
      #
      # @param code [String] a UCUM code such as "mg/L" or "Cel{cells}"
      # @return [RubyUnits::Ucum::Expression]
      # @raise [RubyUnits::Ucum::ParseError] on any syntax error or unsupported code
      def parse(code)
        raise ParseError.new("UCUM code must be a String", 0) unless code.is_a?(::String)

        ast = Parser.parse(code)
        unit = build_unit(ast)
        Expression.new(unit, ast, code)
      end

      # Convert a numeric value between two UCUM codes.
      #
      # @param value [Numeric]
      # @param code [String] source UCUM code
      # @param target_code [String] target UCUM code
      # @return [Numeric]
      def convert(value, code, target_code)
        parse(code).convert(value, target_code)
      end

      # Emit a canonical UCUM code for a parsed AST or a {RubyUnits::Unit}.
      #
      # @param expression_or_unit [RubyUnits::Ucum::Parser::ExpressionNode,
      #   RubyUnits::Ucum::Expression, RubyUnits::Unit]
      # @return [String]
      # @raise [ArgumentError] when a unit cannot be represented in UCUM
      def dump(expression_or_unit)
        case expression_or_unit
        when Expression
          expression_or_unit.to_ucum
        when Parser::ExpressionNode
          emit(expression_or_unit)
        when RubyUnits::Unit
          emit_unit(expression_or_unit)
        else
          raise ArgumentError, "cannot emit UCUM for #{expression_or_unit.inspect}"
        end
      end

      # @api private
      # Build the proportional {RubyUnits::Unit} for a parsed expression.
      # @param ast [RubyUnits::Ucum::Parser::ExpressionNode]
      # @return [RubyUnits::Unit]
      def build_unit(ast)
        numerator = build_term(ast.numerator)
        denominator = ast.denominator ? build_term(ast.denominator) : 1
        numerator / denominator
      end

      # @api private
      # @param term [RubyUnits::Ucum::Parser::TermNode]
      # @return [RubyUnits::Unit]
      def build_term(term)
        term.components.reduce(unit_class.new(1)) { |result, component| result * build_component(component) }
      end

      # @api private
      # @param component [RubyUnits::Ucum::Parser::ComponentNode]
      # @return [RubyUnits::Unit]
      def build_component(component)
        factor_unit = build_factor(component.factor)
        factor_unit ** component.exponent
      end

      # @api private
      def build_factor(factor)
        case factor
        when Parser::AtomNode
          build_atom(factor)
        when Parser::GroupNode
          build_unit(factor.expression)
        end
      end

      # @api private
      # @param atom [RubyUnits::Ucum::Parser::AtomNode]
      # @return [RubyUnits::Unit]
      def build_atom(atom)
        entry = atom.entry
        number = entry[:number]
        if number
          return unit_class.new(parse_factor(number))
        end

        unit = if entry[:kind] == AFFINE
                 unit_class.new("1 #{entry[:degree]}")
               elsif entry[:value].is_a?(Numeric)
                 unit_class.new(entry[:value])
               else
                 unit_class.new("1 #{entry[:value]}")
               end
        apply_prefix(unit, atom.prefix)
      end

      # @api private
      # Emit canonical UCUM for an AST node.
      # @param ast [RubyUnits::Ucum::Parser::ExpressionNode]
      # @return [String]
      def emit(ast)
        numerator = emit_term(ast.numerator)
        denominator = ast.denominator ? emit_term(ast.denominator) : nil
        result = +(denominator ? "#{numerator}/#{denominator}" : numerator)
        result << "{#{ast.annotation}}" if ast.annotation
        result
      end

      # @api private
      # @param term [RubyUnits::Ucum::Parser::TermNode]
      # @return [String]
      def emit_term(term)
        emitted = +term.components.map { emit_component(_1) }.join(".")
        emitted << "{#{term.annotation}}" if term.annotation
        emitted
      end

      # @api private
      # @param component [RubyUnits::Ucum::Parser::ComponentNode]
      # @return [String]
      def emit_component(component)
        factor = component.factor
        emitted = case factor
                  when Parser::AtomNode
                    emit_atom(factor)
                  when Parser::GroupNode
                    "(#{emit(factor.expression)})"
                  end
        emitted << exponent_suffix(component.exponent)
        emitted << "{#{component.annotation}}" if component.annotation
        emitted
      end

      # @api private
      # @param atom [RubyUnits::Ucum::Parser::AtomNode]
      # @return [String]
      def emit_atom(atom)
        number = atom.entry[:number]
        return number if number

        "#{atom.prefix}#{atom.code}"
      end

      # Emit canonical UCUM for an arbitrary {RubyUnits::Unit} that was not
      # necessarily produced by this parser.
      # @param unit [RubyUnits::Unit]
      # @return [String]
      def emit_unit(unit)
        numerator = emit_unit_array(unit.numerator)
        denominator = emit_unit_array(unit.denominator)
        return "" if numerator.empty? && denominator.empty?

        emitted = +(numerator.empty? ? "1" : numerator.join("."))
        emitted << "/#{denominator.join('.')}" unless denominator.empty?
        emitted
      end

      # @api private
      # Convert a RubyUnits numerator/denominator array to UCUM component codes.
      # @param array [Array<String>]
      # @return [Array<String>]
      def emit_unit_array(array)
        return [] if array == RubyUnits::Unit::UNITY_ARRAY || array == %w[<1>]

        components = []
        index = 0
        while index < array.size
          name = array[index]
          if RubyUnits::Unit.definition(name)&.prefix? && index + 1 < array.size
            base_name = array[index + 1]
            components << "#{ucum_prefix(name)}#{ucum_code_for(base_name)}"
            index += 2
          else
            components << ucum_code_for(name)
            index += 1
          end
        end
        combine_exponents(components)
      end

      # @api private
      # Collapse repeated identical codes into exponent form.
      # @param codes [Array<String>]
      # @return [Array<String>]
      def combine_exponents(codes)
        codes.group_by(&:itself).map do |code, occurrences|
          count = occurrences.size
          count == 1 ? code : "#{code}#{count}"
        end
      end

      # Map a RubyUnits internal unit name to its UCUM code.
      # @param internal_name [String] e.g. "<meter>"
      # @return [String]
      def ucum_code_for(internal_name)
        canonical = internal_name.delete("<>")
        code = RUBY_TO_UCUM[canonical]
        return code if code
        definition = RubyUnits::Unit.definition(internal_name)
        alias_code = definition&.aliases&.find { |name| ATOMS.key?(name) }
        return alias_code if alias_code

        raise ArgumentError, "unit '#{canonical}' cannot be represented as a UCUM code"
      end

      # Map a RubyUnits prefix name to its UCUM prefix code.
      # @param internal_name [String] e.g. "<kilo>"
      # @return [String]
      def ucum_prefix(internal_name)
        canonical = internal_name.delete("<>")
        definition = RubyUnits::Unit.definition(internal_name)
        candidates = definition&.aliases || []
        prefix = candidates.find { |name| DECIMAL_PREFIXES.key?(name) }
        return prefix if prefix

        raise ArgumentError, "prefix '#{canonical}' cannot be represented as a UCUM prefix"
      end

      private

      def apply_prefix(unit, prefix_code)
        return unit unless prefix_code

        prefix_name = RubyUnits::Unit.prefix_map[prefix_code]
        unit_class.new(
          scalar: unit.scalar,
          numerator: [prefix_name, *unit.numerator],
          denominator: unit.denominator
        )
      end

      def parse_factor(number)
        if number.match?(/[.eE]/)
          RubyUnits::Unit.parse_number(number)
        else
          Integer(number)
        end
      end

      def exponent_suffix(exponent)
        exponent == 1 ? "" : exponent.to_s
      end

      def unit_class
        RubyUnits::Unit
      end
    end
  end
end
