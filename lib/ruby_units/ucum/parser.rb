# frozen_string_literal: true

module RubyUnits
  class Ucum
    # Raised when a UCUM code cannot be parsed or is not supported.
    #
    # +position+ is the zero-based character offset of the offending code
    # inside the original input string.
    class ParseError < ArgumentError
      # @return [Integer] zero-based position of the offending code
      attr_reader :position

      # @param message [String]
      # @param position [Integer]
      def initialize(message, position)
        @position = position
        super("#{message} at position #{position}")
      end
    end

    # Strictly parses the UCUM subset supported by ruby-units.
    #
    # @see http://unitsofmeasure.org/ucum.html#section-Grammar-of-Unicode-Symbols
    class Parser
      # An atom reference: decimal prefix (if any), UCUM code, and atom entry.
      AtomNode = Struct.new(:prefix, :code, :entry, :position, keyword_init: true)

      # A parenthesized sub-expression.
      GroupNode = Struct.new(:expression, :position, keyword_init: true)

      # An atom or group with an integer exponent and an optional annotation.
      ComponentNode = Struct.new(:factor, :exponent, :annotation, keyword_init: true)

      # A chain of multiplied components, with an optional annotation.
      TermNode = Struct.new(:components, :annotation, keyword_init: true)

      # A numerator term and an optional denominator term.
      ExpressionNode = Struct.new(:numerator, :denominator, :annotation, keyword_init: true)

      # @param input [String] a UCUM unit code (no leading scalar)
      # @return [ExpressionNode]
      def self.parse(input)
        new(input).parse
      end

      # @param input [String]
      def initialize(input)
        raise ParseError.new("UCUM code must be a String", 0) unless input.is_a?(::String)

        @input = input
        @pos = 0
      end

      # @return [ExpressionNode]
      def parse
        raise ParseError.new("UCUM code is empty", 0) if @input.strip.empty?

        expression = parse_expression
        expression.annotation = read_annotation
        raise ParseError.new("unexpected character '#{@input[@pos]}'", @pos) unless at_end?

        validate_affine(expression)
        expression
      end

      private

      # expression ::= term ("/" term)?
      def parse_expression
        numerator = parse_term
        denominator = nil
        if @input[@pos] == "/"
          @pos += 1
          raise ParseError.new("expected a unit after '/'", @pos) if at_end? || peek_one_of?("/", ")", "{")

          denominator = parse_term
        end
        ExpressionNode.new(numerator: numerator, denominator: denominator)
      end

      # term ::= component (("." | implicit) component)* [annotation]
      def parse_term
        components = [parse_component]
        loop do
          break if at_end? || peek_one_of?("/", ")", "{")
          if @input[@pos] == "."
            @pos += 1
            # A digit after a dot starts another numeric factor (e.g. "100.m"),
            # while a dot between digits is part of a decimal number.
            break if at_end? || peek_one_of?("/", ")", "{")
          end
          components << parse_component
        end
        TermNode.new(components: components, annotation: read_annotation)
      end

      # component ::= factor annotation? exponent? annotation?
      # factor ::= number | prefix? atom | "(" expression ")"
      def parse_component
        factor = if @input[@pos] == "("
                   start = @pos
                   @pos += 1
                   expression = parse_expression
                   unless @input[@pos] == ")"
                     raise ParseError.new("expected ')'", @pos.clamp(0, @input.length))
                   end
                   @pos += 1
                   GroupNode.new(expression: expression, position: start)
                 else
                   parse_atom
                 end
        annotation = read_annotation
        ComponentNode.new(factor: factor, exponent: parse_exponent, annotation: annotation || read_annotation)
      end

      # factor ::= number | (decimal-prefix? atom)
      def parse_atom
        start = @pos
        number_text = scan_number
        return AtomNode.new(prefix: nil, code: nil, entry: { number: number_text }, position: start) if number_text

        token, position = scan_atom_token
        prefix, code, entry = resolve_atom(token, position)
        if entry[:kind] == SPECIAL
          raise ParseError.new("UCUM special unit '#{code}' (#{entry[:function]}) is not supported", position)
        end

        AtomNode.new(prefix: prefix, code: code, entry: entry, position: position)
      end

      # exponent ::= ("^")? signed-integer
      def parse_exponent
        if @input[@pos] == "^"
          @pos += 1
          digits = @input[@pos..].slice(/\A[+-]?\d+/)
          raise ParseError.new("expected an exponent after '^'", @pos) unless digits
          @pos += digits.length
          return Integer(digits)
        end
        digits = @input[@pos..].slice(/\A[+-]?\d+/)
        return 1 unless digits

        @pos += digits.length
        Integer(digits)
      end

      # annotation ::= "{" text "}"
      def read_annotation
        return nil unless @input[@pos] == "{"

        start = @pos
        close = @input.index("}", start + 1)
        raise ParseError.new("unterminated UCUM annotation", start) unless close

        annotation = @input[(start + 1)...close]
        @pos = close + 1
        annotation
      end

      # Scan a bare numeric factor such as "10" or "10.5". A number directly
      # followed by a simple atom (e.g. "10.5m") is still consumed here; the
      # following atom is parsed as a separate implicit factor.
      # @return [String, nil] the matched number text
      def scan_number
        rest = @input[@pos..]
        scientific = rest.slice(/\A\d+(?:\.\d+)?[eE][+-]?\d+/)
        if scientific
          @pos += scientific.length
          return scientific
        end
        plain = rest.slice(/\A\d+(?:\.\d+)?/)
        return unless plain

        @pos += plain.length
        plain
      end

      # Scan the raw atom token: bracketed or simple.
      def scan_atom_token
        position = @pos
        if @input[@pos] == "["
          close = @input.index("]", position + 1)
          raise ParseError.new("unterminated UCUM bracketed unit", position) unless close

          token = @input[position..close]
          @pos = close + 1
          return [token, position]
        end

        token = @input[@pos..].slice(/\A[A-Za-z_][A-Za-z_]*/) || @input[@pos..].slice(/\A%/)
        raise ParseError.new("unexpected character '#{@input[@pos]}'", position) unless token

        @pos += token.length
        [token, position]
      end

      # Resolve a raw token against the atom table, trying decimal prefixes.
      # Prefix matching is strictly case sensitive and longest-prefix first.
      def resolve_atom(token, position)
        exact = ATOMS[token]
        if exact
          [nil, token, exact]
        elsif (prefix = matching_prefix(token)) && (atom = ATOMS[token[prefix.length..]]) && atom[:prefixable]
          [prefix, token[prefix.length..], atom]
        else
          raise ParseError.new("unknown UCUM unit code '#{token}'", position)
        end
      end

      # @return [String, nil] the longest decimal prefix that starts +token+
      def matching_prefix(token)
        DECIMAL_PREFIXES.keys.sort_by(&:length).reverse.find { token.start_with?(_1) }
      end

      # Affine units may only appear as a sole term with exponent 1; they can
      # never be grouped, divided, multiplied with anything, or exponentiated.
      def validate_affine(expression)
        each_affine(expression) do |atom, component, containing|
          allowed = component.exponent == 1 && containing.nil? &&
                    expression.denominator.nil? && expression.numerator.components.size == 1
          unless allowed
            raise ParseError.new("affine unit '#{atom.code}' cannot be multiplied, divided, or raised to a power", atom.position)
          end
        end
      end

      # Yields each affine atom together with its component and the group
      # (if any) that directly contains it.
      def each_affine(expression, containing = nil, &block)
        [expression.numerator, expression.denominator].compact.each do |term|
          term.components.each do |component|
            factor = component.factor
            case factor
            when AtomNode
              yield(factor, component, containing) if factor.entry[:kind] == AFFINE
            when GroupNode
              each_affine(factor.expression, factor, &block)
            end
          end
        end
      end

      def peek_one_of?(*chars)
        chars.include?(@input[@pos])
      end

      def at_end?
        @pos >= @input.length
      end
    end
  end
end
