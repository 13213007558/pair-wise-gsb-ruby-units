# frozen_string_literal: true

require "strscan"

module RubyUnits
  module Ucum
    # Strict, case-sensitive recursive descent parser for a practical subset
    # of the UCUM grammar:
    #
    #   term        ::= component (('.' | '/') component)*
    #   component   ::= base exponent? annotation?
    #   base        ::= atom | factor | '(' term ')' | '[' term ']'
    #   atom        ::= case-sensitive simple unit code (optionally prefixed)
    #   factor      ::= digits ('^' signed-digits)?
    #   exponent    ::= ('+' | '-')? digits (immediately following the base)
    #   annotation  ::= '{' ... '}' (nested braces allowed)
    #
    # Whitespace is not allowed inside formal UCUM codes. Square brackets are
    # accepted for grouping per the UCUM convention that they are equivalent
    # to parentheses whenever they do not delimit a special unit code.
    class Parser
      # @param source [String]
      # @param offset [Integer] absolute source position of +source+
      # @return [Nodes::Term]
      def self.parse(source, offset = 0)
        unless source.is_a?(::String) && !source.empty?
          raise ParseError.new("UCUM code must be a non-empty String", source.to_s, 0)
        end

        new(source, offset).parse!
      end

      # @param source [String]
      # @param offset [Integer]
      def initialize(source, offset = 0)
        @source = source
        @offset = offset
        @scanner = StringScanner.new(source)
      end

      # @return [Nodes::Term]
      def parse!
        term = read_term
        unless @scanner.eos?
          raise ParseError.new("unexpected trailing text", @source, @offset + @scanner.pos)
        end
        term
      end

      private

      # @return [Nodes::Term]
      def read_term
        start = @scanner.pos
        components = []
        denominators = []

        components << read_component
        denominators << false

        loop do
          separator = @scanner.scan(/[.\/]/)
          if separator.nil?
            # UCUM permits adjacent components (implicit multiplication),
            # primarily used to attach a numeric factor to a unit (10^3Pa).
            factor_component = components.last.base.is_a?(::Numeric)
            break unless factor_component && @scanner.match?(/[A-Za-z%(\[]/)
          elsif @scanner.eos? || @scanner.match?(/[.)\]]/)
            error!("expected a component after '#{separator}'", @scanner.pos - 1)
          end
          components << read_component
          denominators << (separator == "/")
        end

        Nodes::Term.new(components: components, denominators: denominators, position: start)
      end

      # @return [Nodes::Component]
      def read_component
        position = @scanner.pos
        base = read_base(position)
        exponent = read_exponent
        annotation = read_annotation
        error!("whitespace is not allowed in UCUM codes", @scanner.pos) if @scanner.match?(/\s/)
        Nodes::Component.new(base: base, exponent: exponent, position: position, annotation: annotation)
      end

      # @param position [Integer]
      # @return [Nodes::Atom, Nodes::Term, Numeric]
      def read_base(position)
        char = @scanner.peek(1)
        case char
        when "(", "["
          read_group(char, position)
        when /\s/
          error!("whitespace is not allowed in UCUM codes", position)
        when /\d/
          read_factor(position)
        else
          read_atom(position)
        end
      end

      # @param opening [String]
      # @param position [Integer]
      # @return [Nodes::Term]
      def read_group(opening, position)
        closing = opening == "(" ? ")" : "]"
        @scanner.getch

        if opening == "["
          bracket_start = @scanner.pos
          inner = @scanner.scan_until(/\]/)
          if inner
            code = inner.delete_suffix("]")
            function = CodeTables::BRACKET_SPECIAL_FUNCTIONS["[#{code}]"]
            if function
              raise UnsupportedSpecialError.new(function, @source, @offset + bracket_start - 1)
            end

            nested = self.class.new(code, @offset + bracket_start).parse!
            return Nodes::Term.new(
              components: nested.components,
              denominators: nested.denominators,
              position: position,
              bracket: "["
            )
          end
        end

        term = read_term
        error!("expected '#{closing}'", @scanner.pos) unless @scanner.getch == closing
        term
      end

      # @param position [Integer]
      # @return [Numeric]
      def read_factor(position)
        digits = @scanner.scan(/\d+/) or error!("expected a numeric factor", position)
        factor = digits.to_i
        return factor unless @scanner.scan(/\^/)

        signed = @scanner.scan(/[+-]?\d+/) or error!("expected an exponent after '^'", @scanner.pos)
        factor**signed.to_i
      end

      # @param position [Integer]
      # @return [Nodes::Atom]
      def read_atom(position)
        code = @scanner.scan(/[A-Za-z%][A-Za-z']*/) or error!("expected a UCUM unit", position)
        descriptor = CodeTables.resolve(code)

        if descriptor.nil?
          error!("unknown or unsupported UCUM unit '#{code}'", position)
        elsif descriptor[:type] == :special
          raise UnsupportedSpecialError.new(descriptor[:function], @source, @offset + position)
        end

        Nodes::Atom.new(
          descriptor: descriptor,
          code: code,
          position: position,
          prefix: descriptor[:prefix]
        )
      end

      # Exponents immediately follow a base. UCUM permits signed or unsigned
      # integers, so +m2+, +m-2+, and +m+2+ are all accepted.
      # @return [Integer]
      def read_exponent
        position = @scanner.pos
        marker = @scanner.scan(/[+-]/)
        digits = @scanner.scan(/\d+/)
        return 1 if marker.nil? && digits.nil?
        error!("expected an exponent", position) if digits.nil?

        (marker.to_s + digits).to_i
      end

      # @return [String, nil] annotation including the surrounding braces
      def read_annotation
        return nil unless @scanner.scan(/\{/)

        depth = 1
        start = @scanner.pos - 1
        until depth.zero?
          char = @scanner.getch
          error!("unterminated annotation", start) if char.nil?
          depth += 1 if char == "{"
          depth -= 1 if char == "}"
        end
        @source[start...@scanner.pos]
      end

      # @param message [String]
      # @param position [Integer]
      def error!(message, position)
        raise ParseError.new(message, @source, @offset + position)
      end
    end
  end
end
