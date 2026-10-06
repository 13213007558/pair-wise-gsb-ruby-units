# frozen_string_literal: true

require_relative "nondimensional/expression"

module RubyUnits
  module Nondimensional
    DimensionMismatch = Class.new(ArgumentError)
    MissingScale = Class.new(ArgumentError)
    InvalidScale = Class.new(ArgumentError)

    Result = Struct.new(:expression, :dimensions, :scale, :variable_scales, :time_scale, :restoration, keyword_init: true)
    VariableRule = Struct.new(:original, :dimensionless, :scale, :dimensions, keyword_init: true)
    TimeRule = Struct.new(:original, :dimensionless, :scale, keyword_init: true)
    DerivativeRule = Struct.new(:order, :expression, :dimensionless_expression, :scale, keyword_init: true)
    Restoration = Struct.new(:variables, :time, :derivatives, :result_scale, :description, keyword_init: true)

    Analysis = Struct.new(:dimensions, :scale, :dimensionless, keyword_init: true)

    class Analyzer
      attr_reader :dimensions, :scales, :time_scale, :time_name

      def initialize(dimensions:, scales:, time_scale:, time_name:)
        @dimensions = normalize_dimensions(dimensions, time_name)
        @scales = normalize_scales(scales, time_name)
        @time_scale = exact_number(time_scale)
        @time_name = time_name.to_sym
      end

      def inspect(node)
        Analysis.new(
          dimensions: dimensions_for(node),
          scale: scale_for(node),
          dimensionless: dimensionless_for(node)
        )
      end

      private

      def dimensions_for(node)
        case node
        when Number
          {}
        when Variable
          variable_dimensions(node.name)
        when Addition, Subtraction
          addition_dimensions(node)
        when Multiplication
          add_dimensions(dimensions_for(node.left), dimensions_for(node.right))
        when Division
          add_dimensions(dimensions_for(node.left), multiply_dimension(dimensions_for(node.right), -1))
        when Power
          multiply_dimension(dimensions_for(node.base), node.exponent)
        when TimeDerivative
          check_derivative_time!(node)
          add_dimensions(dimensions_for(node.expression), { time: -node.order })
        else
          raise ArgumentError, "unsupported expression: " + node.class.name
        end
      end

      def variable_dimensions(name)
        return { time: 1 } if name == time_name

        fetch_dimension(name)
      end

      def addition_dimensions(node)
        left = dimensions_for(node.left)
        right = dimensions_for(node.right)
        unless left == right
          raise DimensionMismatch.new(
            "cannot add expressions with dimensions " +
              left.inspect + " and " + right.inspect
          )
        end
        left
      end

      def scale_for(node)
        case node
        when Number
          1
        when Variable
          variable_scale(node.name)
        when Addition, Subtraction
          addition_scale(node)
        when Multiplication
          scale_for(node.left) * scale_for(node.right)
        when Division
          scale_for(node.left) / scale_for(node.right)
        when Power
          scale_for(node.base)**node.exponent
        when TimeDerivative
          check_derivative_time!(node)
          scale_for(node.expression) / (time_scale**node.order)
        else
          raise ArgumentError, "unsupported expression: " + node.class.name
        end
      end

      def variable_scale(name)
        return time_scale if name == time_name

        fetch_scale(name)
      end

      def addition_scale(node)
        branch = addition_branches(node).first
        scale = scale_for(branch)
        return scale unless scale.respond_to?(:zero?) && scale.zero?

        raise InvalidScale, "reference scale for an addition branch must not be zero"
      end

      def addition_branches(node)
        return [node] unless node.is_a?(Addition) || node.is_a?(Subtraction)

        addition_branches(node.left) + [node.right]
      end

      def dimensionless_for(node)
        case node
        when Number
          Number.new(node.value)
        when Variable
          Variable.new(node.name == time_name ? :tau : dimensionless_name(node.name))
        when Addition, Subtraction
          dimensionless_addition(node)
        when Multiplication
          Multiplication.new(dimensionless_for(node.left), dimensionless_for(node.right))
        when Division
          Division.new(dimensionless_for(node.left), dimensionless_for(node.right))
        when Power
          Power.new(dimensionless_for(node.base), node.exponent)
        when TimeDerivative
          check_derivative_time!(node)
          TimeDerivative.new(dimensionless_for(node.expression), node.order, time_name: :tau)
        else
          raise ArgumentError, "unsupported expression: " + node.class.name
        end
      end

      def dimensionless_addition(node)
        reference_scale = addition_scale(node)
        check_addition_dimensions(node)
        left = dimensionless_addition_branch(node.left, reference_scale)
        right = dimensionless_branch(node.right, reference_scale)
        node.class.new(left, right)
      end

      def dimensionless_addition_branch(node, reference_scale)
        if node.is_a?(Addition) || node.is_a?(Subtraction)
          check_addition_dimensions(node)
          left = dimensionless_addition_branch(node.left, reference_scale)
          right = dimensionless_branch(node.right, reference_scale)
          return node.class.new(left, right)
        end

        dimensionless_branch(node, reference_scale)
      end

      def check_addition_dimensions(node)
        dimensions = addition_dimension_list(node)
        dimensions.each_cons(2) do |left, right|
          next if left == right

          raise DimensionMismatch.new(
            "cannot add expressions with dimensions " + left.inspect + " and " + right.inspect
          )
        end
      end

      def addition_dimension_list(node)
        addition_branches(node).map { |branch| dimensions_for(branch) }
      end

      def dimensionless_branch(node, reference_scale)
        dimensionless = dimensionless_for(node)
        factor = scale_for(node) / reference_scale
        return dimensionless if factor == 1

        Multiplication.new(Number.new(factor), dimensionless)
      end

      def add_dimensions(left, right)
        left.merge(right) { |_, left_power, right_power| left_power + right_power }
            .delete_if { |_, power| power.zero? }
      end

      def multiply_dimension(dimensions, multiplier)
        dimensions.each_with_object({}) do |(name, power), result|
          result[name] = power * multiplier
        end
      end

      def check_derivative_time!(node)
        return if node.time_name == time_name

        raise ArgumentError, "derivative time does not match reference time"
      end

      def dimensionless_name(name)
        (name.to_s + "_hat").to_sym
      end

      def fetch_dimension(name)
        dimensions.fetch(name) do
          raise MissingScale, "missing dimensions for variable " + name.to_s
        end
      end

      def fetch_scale(name)
        scales.fetch(name) do
          raise MissingScale, "missing reference scale for variable " + name.to_s
        end
      end

      def normalize_dimensions(input, time_name)
        input.each_with_object({}) do |(name, powers), result|
          symbol = name.to_sym
          next if symbol == time_name.to_sym

          normalized = powers.transform_keys(&:to_sym).reject { |_, power| power.zero? }
          result[symbol] = normalized
        end
      end

      def normalize_scales(input, time_name)
        input.each_with_object({}) do |(name, scale), result|
          symbol = name.to_sym
          next if symbol == time_name.to_sym

          validate_scale!(scale, symbol)
          result[symbol] = exact_number(scale)
        end
      end

      def validate_scale!(scale, name)
        return if scale.is_a?(Numeric) && !scale.is_a?(Complex) && scale.positive?

        raise InvalidScale, "reference scale for " + name.to_s + " must be a positive number"
      end

      def exact_number(number)
        return number.to_r if number.is_a?(Float)
        return Rational(number, 1) if number.is_a?(Integer)

        number
      end
    end

    def number(value)
      Number.new(value)
    end
    def num(value)
      number(value)
    end
    module_function :number
    module_function :num

    def variable(name)
      Variable.new(name)
    end
    def var(name)
      variable(name)
    end
    module_function :variable
    module_function :var

    def self.transform(expression, dimensions:, scales:, time_scale:, time_name: :t)
      unless expression.is_a?(Expression)
        raise ArgumentError, "expression must be an Expression node"
      end
      validate_dimensions!(dimensions)
      validate_scales!(scales)

      validate_time_scale!(time_scale)
      analyzer = Analyzer.new(dimensions: dimensions, scales: scales, time_scale: time_scale, time_name: time_name)
      result = analyzer.inspect(expression)
      restoration = build_restoration(expression, result, analyzer, analyzer.time_scale, time_name)
      Result.new(
        expression: result.dimensionless,
        dimensions: result.dimensions,
        scale: result.scale,
        variable_scales: analyzer.scales,
        time_scale: analyzer.time_scale,
        restoration: restoration
      )
    end

    class << self
      private

      def validate_time_scale!(time_scale)
        return if time_scale.is_a?(Numeric) && !time_scale.is_a?(Complex) && time_scale.positive?

        raise InvalidScale, "time reference scale must be a positive number"
      end

      def validate_dimensions!(dimensions)
        return if dimensions.is_a?(Hash) && dimensions.all? do |_, powers|
          powers.is_a?(Hash) && powers.all? do |dimension, power|
            dimension.respond_to?(:to_sym) && power.is_a?(Integer)
          end
        end

        raise ArgumentError, "dimensions must map each variable to integer base-dimension powers"
      end

      def validate_scales!(scales)
        return if scales.is_a?(Hash)

        raise ArgumentError, "scales must map each variable to a positive reference scale"
      end

      def build_restoration(expression, result, analyzer, time_scale, time_name)
        variables = collect_variables(expression)
                     .uniq(&:name)
                     .reject { |variable| variable.name == time_name }
                     .map do |variable|
                       VariableRule.new(
                         original: variable.name,
                         dimensionless: analyzer.send(:dimensionless_name, variable.name),
                         scale: analyzer.scales.fetch(variable.name),
                         dimensions: analyzer.dimensions.fetch(variable.name)
                       )
                     end
        derivatives = collect_derivatives(expression)
                       .uniq { |node| [node.expression, node.order] }
                       .map do |node|
                         inner = analyzer.inspect(node.expression)
                         DerivativeRule.new(
                           order: node.order,
                           expression: node.expression.to_s,
                           dimensionless_expression: inner.dimensionless.to_s,
                           scale: inner.scale / (time_scale**node.order)
                         )
                       end
        time = TimeRule.new(original: time_name, dimensionless: :tau, scale: time_scale)
        Restoration.new(
          variables: variables,
          time: time,
          derivatives: derivatives,
          result_scale: result.scale,
          description: restoration_description(variables, time, derivatives, result.scale)
        )
      end

      def collect_variables(node)
        case node
        when Variable
          [node]
        when TimeDerivative
          collect_variables(node.expression)
        when BinaryExpression
          collect_variables(node.left) + collect_variables(node.right)
        when Power
          collect_variables(node.base)
        else
          []
        end
      end

      def collect_derivatives(node)
        case node
        when TimeDerivative
          [node]
        when BinaryExpression
          collect_derivatives(node.left) + collect_derivatives(node.right)
        when Power
          collect_derivatives(node.base)
        else
          []
        end
      end

      def restoration_description(variables, time, derivatives, result_scale)
        lines = [time.original.to_s + " = " + format_number(time.scale) + " " + time.dimensionless.to_s]
        variables.each do |variable|
          lines << variable.original.to_s + " = " + format_number(variable.scale) + " " + variable.dimensionless.to_s
        end
        derivatives.each do |derivative|
          lines << derivative_description(derivative, time)
        end
        lines << "original residual = " + format_number(result_scale) + " dimensionless residual"
        lines.join("\n")
      end

      def derivative_description(derivative, time)
        "d^" + derivative.order.to_s + "(" + derivative.expression + ")/d" + time.original.to_s + "^" +
          derivative.order.to_s + " = " + format_number(derivative.scale) + " d^" +
          derivative.order.to_s + "(" + derivative.dimensionless_expression + ")/d" +
          time.dimensionless.to_s + "^" + derivative.order.to_s
      end

      def format_number(number)
        return number.numerator.to_s if number.is_a?(Rational) && number.denominator == 1

        number.to_s
      end
    end
  end
end
