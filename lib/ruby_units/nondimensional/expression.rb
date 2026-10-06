# frozen_string_literal: true

module RubyUnits
  module Nondimensional
    class Expression
      def +(other)
        raise ArgumentError, "expression operand must be an Expression" unless other.is_a?(Expression)
        Addition.new(self, other)
      end

      def -(other)
        raise ArgumentError, "expression operand must be an Expression" unless other.is_a?(Expression)
        Subtraction.new(self, other)
      end

      def *(other)
        raise ArgumentError, "expression operand must be an Expression" unless other.is_a?(Expression)
        Multiplication.new(self, other)
      end

      def /(other)
        raise ArgumentError, "expression operand must be an Expression" unless other.is_a?(Expression)
        Division.new(self, other)
      end

      def **(exponent)
        Power.new(self, exponent)
      end

      def ddt(order = 1, time_name: :t)
        TimeDerivative.new(self, order, time_name: time_name)
      end

      def evaluate(values = {}, derivatives: {})
        Evaluator.new(values, derivatives: derivatives).evaluate(self)
      end
    end

    class Number < Expression
      attr_reader :value

      def initialize(value)
        super()
        unless value.is_a?(Numeric)
          raise ArgumentError, "number value must be numeric"
        end

        @value = value.freeze
      end

      def ==(other)
        other.is_a?(Number) && value == other.value
      end
      alias eql? ==

      def hash
        [self.class, value].hash
      end

      def to_s
        value.to_s
      end
    end

    class Variable < Expression
      attr_reader :name

      def initialize(name)
        super()
        @name = name.to_sym
      end

      def ==(other)
        other.is_a?(Variable) && name == other.name
      end
      alias eql? ==

      def hash
        [self.class, name].hash
      end

      def to_s
        name.to_s
      end
    end

    class BinaryExpression < Expression
      attr_reader :left, :right

      def initialize(left, right)
        super()
        unless left.is_a?(Expression) && right.is_a?(Expression)
          raise ArgumentError, "expression operands must be Expression nodes"
        end

        @left = left
        @right = right
      end

      def ==(other)
        other.class == self.class && other.left == left && other.right == right
      end
      alias eql? ==

      def hash
        [self.class, left, right].hash
      end
    end

    class Addition < BinaryExpression
      def to_s
        "(" + left.to_s + " + " + right.to_s + ")"
      end
    end

    class Subtraction < BinaryExpression
      def to_s
        "(" + left.to_s + " - " + right.to_s + ")"
      end
    end

    class Multiplication < BinaryExpression
      def to_s
        "(" + left.to_s + " * " + right.to_s + ")"
      end
    end

    class Division < BinaryExpression
      def to_s
        "(" + left.to_s + " / " + right.to_s + ")"
      end
    end

    class Power < Expression
      attr_reader :base, :exponent

      def initialize(base, exponent)
        super()
        unless base.is_a?(Expression)
          raise ArgumentError, "power base must be an Expression"
        end

        unless exponent.is_a?(Integer)
          raise ArgumentError, "power exponent must be an integer"
        end

        @base = base
        @exponent = exponent
      end

      def ==(other)
        other.is_a?(Power) && other.base == base && other.exponent == exponent
      end
      alias eql? ==

      def hash
        [self.class, base, exponent].hash
      end

      def to_s
        base.to_s + "^" + exponent.to_s
      end
    end

    class TimeDerivative < Expression
      attr_reader :expression, :order, :time_name

      def initialize(expression, order = 1, time_name: :t)
        super()
        unless expression.is_a?(Expression)
          raise ArgumentError, "derivative expression must be an Expression"
        end

        unless order.is_a?(Integer) && order.positive?
          raise ArgumentError, "derivative order must be a positive integer"
        end

        @expression = expression
        @order = order
        @time_name = time_name.to_sym
      end

      def ==(other)
        other.is_a?(TimeDerivative) && other.expression == expression &&
          other.order == order && other.time_name == time_name
      end
      alias eql? ==

      def hash
        [self.class, expression, order, time_name].hash
      end

      def to_s
        "d^" + order.to_s + "(" + expression.to_s + ")/d" + time_name.to_s + "^" + order.to_s
      end
    end

    class Evaluator
      def initialize(values, derivatives: {})
        @values = values.transform_keys(&:to_sym)
        @derivatives = derivatives
      end

      def evaluate(node)
        case node
        when Number
          node.value
        when Variable
          value_for(node.name)
        when Addition
          evaluate(node.left) + evaluate(node.right)
        when Subtraction
          evaluate(node.left) - evaluate(node.right)
        when Multiplication
          evaluate(node.left) * evaluate(node.right)
        when Division
          evaluate(node.left) / evaluate(node.right)
        when Power
          evaluate(node.base)**node.exponent
        when TimeDerivative
          derivative_for(node)
        else
          raise ArgumentError, "unsupported expression: #{node.class}"
        end
      end

      private

      def value_for(name)
        return @values.fetch(name) if @values.key?(name)

        raise ArgumentError, "missing value for variable #{name}"
      end

      def derivative_for(node)
        by_order = derivatives_for(node.expression)
        return by_order.fetch(node.order) if by_order.key?(node.order)

        raise ArgumentError, "missing order #{node.order} derivative for #{node.expression}"
      end

      def derivatives_for(expression)
        @derivatives.fetch(expression) do
          name = expression.is_a?(Variable) ? expression.name : expression
          @derivatives.fetch(name) { {} }
        end
      end
    end
  end
end
