# frozen_string_literal: true

module RubyUnits
  module Ucum
    # Serializes parsed UCUM ASTs and {RubyUnits::Unit} objects back into
    # canonical UCUM codes.
    module Serializer
      module_function

      # Emit a parsed AST without canonicalizing through a Unit. This keeps
      # annotations and the input's multiplicative structure.
      #
      # @param tree [Nodes::Term]
      # @return [String]
      def dump_tree(tree)
        render_term(tree)
      end

      # Canonicalize a Unit produced from a UCUM code.
      #
      # @param unit [RubyUnits::Unit]
      # @return [String]
      # @raise [OutputError] when the Unit contains non-UCUM definitions or a
      #   scalar that cannot be written as a UCUM factor
      def dump(unit)
        tokens = tokenize(unit)
        numerator = canonical_codes(group_tokens(tokens[:numerator]))
        denominator = canonical_codes(group_tokens(tokens[:denominator]))
        factor = Rational(unit.scalar.to_r)

        remaining_factor, numerator = absorb_single_prefix_factor(factor, numerator)
        parts = factor_parts(remaining_factor)
        numerator.unshift(*parts[:numerator])
        denominator.unshift(*parts[:denominator])

        numerator = [["1", 1]] if numerator.empty?
        num = format_codes(numerator)
        return num if denominator.empty?

        "#{num}/#{format_codes(denominator)}"
      end

      # @param tree [Nodes::Term]
      # @return [String]
      def render_term(tree)
        numerator = []
        denominator = []
        tree.components.zip(tree.denominators) do |component, is_denominator|
          code = render_component(component)
          is_denominator ? denominator << code : numerator << code
        end
        num = numerator.join(".")
        num = "1" if num.empty?
        denominator.empty? ? num : "#{num}/#{denominator.join('.')}"
      end

      # @param component [Nodes::Component]
      # @return [String]
      def render_component(component)
        base_code = case component.base
                    when Nodes::Atom
                      atom_code(component.base)
                    when ::Numeric
                      numeric_code(component.base)
                    when Nodes::Term
                      group_code(component.base)
                    end
        with_exponent(base_code, component.exponent) + component.annotation.to_s
      end

      # @param term [Nodes::Term]
      # @return [String]
      def group_code(term)
        opening = term.bracket == "[" ? "[" : "("
        closing = term.bracket == "[" ? "]" : ")"
        "#{opening}#{render_term(term)}#{closing}"
      end

      # @param atom [Nodes::Atom]
      # @return [String]
      def atom_code(atom)
        descriptor = atom.descriptor
        return numeric_atom_code(atom.code) if descriptor[:type] == :numeric
        return "Cel" if descriptor[:type] == :affine

        unit_code = CodeTables::UNIT_CODES.fetch(descriptor[:unit]) { raise OutputError, "unit #{descriptor[:unit].inspect} has no UCUM code" }
        "#{atom.prefix}#{unit_code}"
      end

      # @param code [String]
      # @return [String]
      def numeric_atom_code(code)
        code == "[pi]" ? "[pi]" : "%"
      end

      # @param value [Numeric]
      # @return [String]
      def numeric_code(value)
        rational = Rational(value.to_r)
        return rational.numerator.to_s if rational.denominator == 1
        return "1/#{rational.denominator}" if rational.numerator == 1

        raise OutputError, "numeric factor #{value.inspect} cannot be emitted as UCUM"
      end

      # @param code [String]
      # @param exponent [Integer]
      # @return [String]
      def with_exponent(code, exponent)
        return code if exponent == 1
        "#{code}#{exponent}"
      end

      # @param unit [RubyUnits::Unit]
      # @return [Hash{Symbol => Array<String>}]
      def tokenize(unit)
        {
          numerator: unit.numerator.reject { |token| token == RubyUnits::Unit::UNITY },
          denominator: unit.denominator.reject { |token| token == RubyUnits::Unit::UNITY }
        }
      end

      # Group consecutive +<prefix><unit>+ tokens into chunks.
      #
      # @param tokens [Array<String>]
      # @return [Array<Hash{Symbol => String, nil}>]
      def group_tokens(tokens)
        chunks = []
        index = 0
        while index < tokens.size
          token = tokens[index]
          definition = definition!(token)
          if definition.prefix? && index + 1 < tokens.size
            chunks << { prefix: token, unit: tokens[index + 1] }
            index += 2
          else
            chunks << { prefix: nil, unit: token }
            index += 1
          end
        end
        chunks
      end

      # @param chunks [Array<Hash>]
      # @return [Array<Array(String, Integer)>] [code, count] pairs
      def canonical_codes(chunks)
        codes = chunks.map do |chunk|
          unit_code = CodeTables::UNIT_CODES.fetch(definition_name(chunk[:unit])) do
            raise OutputError, "unit #{definition_name(chunk[:unit]).inspect} has no UCUM code"
          end
          prefix_code = chunk[:prefix] ? prefix_code!(chunk[:prefix]) : ""
          "#{prefix_code}#{unit_code}"
        end
        tally(codes)
      end

      # When the factor is exactly one decimal prefix and there is a single
      # numerator chunk, emit the prefixed form (1000 + m => km).
      #
      # @param factor [Rational]
      # @param numerator [Array<Array(String, Integer)>]
      # @return [Array(Rational, Array<Array(String, Integer)>)]
      def absorb_single_prefix_factor(factor, numerator)
        prefix = CodeTables::SI_PREFIXES.find { |_, value| Rational(value.to_r) == factor }
        return [factor, numerator] unless prefix
        return [factor, numerator] unless numerator.size == 1 && numerator.first.last == 1

        [Rational(1), [["#{prefix.first}#{numerator.first.first}", 1]]]
      end

      # Split the scalar into explicit UCUM numeric factors. A decimal prefix
      # is only used when no single-chunk prefix match was possible.
      #
      # @param scalar [Numeric]
      # @return [Hash{Symbol => Array<Array(String, Integer)>}]
      def factor_parts(scalar)
        rational = Rational(scalar.to_r)
        return { numerator: [], denominator: [] } if rational == 1

        if rational.denominator == 1
          { numerator: [[power_of_ten_code(rational.numerator), 1]], denominator: [] }
        elsif rational.numerator == 1
          { numerator: [], denominator: [[power_of_ten_code(rational.denominator), 1]] }
        else
          raise OutputError, "scalar #{scalar.inspect} cannot be represented as a UCUM factor"
        end
      end

      # Emit an integer using UCUM factor notation (100 => 10^2).
      #
      # @param value [Integer]
      # @return [String]
      def power_of_ten_code(value)
        return value.to_s unless power_of_ten?(value)

        power = 0
        power += 1 while (10**power) < value
        power.zero? ? value.to_s : "10^#{power}"
      end

      # @param value [Integer]
      # @return [Boolean]
      def power_of_ten?(value)
        reduced = value
        reduced /= 10 while (reduced % 10).zero? && reduced > 1
        reduced == 1
      end

      # @param pairs [Array<Array(String, Integer)>]
      # @return [String]
      def format_codes(pairs)
        pairs.map { |code, count| with_exponent(code, count) }.join(".")
      end

      # @param codes [Array<String>]
      # @return [Array<Array(String, Integer)>]
      def tally(codes)
        counts = ::Hash.new(0)
        codes.each { counts[_1] += 1 }
        counts.sort_by(&:first).map { |code, count| [code, count] }
      end

      # @param token [String]
      # @return [RubyUnits::Unit::Definition]
      def definition!(token)
        RubyUnits::Unit.definition(token) || raise(OutputError, "#{token.inspect} is not a known unit")
      end

      # @param token [String]
      # @return [String]
      def definition_name(token)
        token.delete("<>")
      end

      # @param token [String]
      # @return [String]
      def prefix_code!(token)
        CodeTables::PREFIX_CODES.fetch(definition_name(token)) do
          raise OutputError, "prefix #{definition_name(token).inspect} has no UCUM code"
        end
      end
    end
  end
end
