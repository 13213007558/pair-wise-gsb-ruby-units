# frozen_string_literal: true

module RubyUnits
  # Tools for rewriting a physical expression in dimensionless form before
  # handing it to a numerical solver.
  #
  # Expressions are built as small node trees (no string evaluation and no
  # external symbolic-math dependency):
  #
  #   include RubyUnits::Nondimensionalize
  #   x = Variable.new(:x, "m")
  #   expr = Constant.new(2, "kg") * x.ddt(2) +
  #          Constant.new(0.5, "N*s/m") * x.ddt +
  #          Constant.new(10, "N/m") * x
  #
  #   context = Context.new(time_scale: RubyUnits::Unit.new("1 s"),
  #                         scales: { x: RubyUnits::Unit.new("0.1 m"), m: RubyUnits::Unit.new("2 kg") })
  #   result = context.nondimensionalize(expr)
  #   result.expression #=> dimensionless tree, safe to hand to a solver
  #   result.restores   #=> human readable instructions to recover SI values
  #
  # Every addition/subtraction branch is checked for compatible dimensions,
  # and time derivatives of order n pick up a factor of the time scale**n.
  module Nondimensionalize
    # Raised when expression branches have incompatible dimensions or when no
    # reference scale is available for a dimension appearing in the expression.
    class DimensionError < ArgumentError; end

    # Base class for expression nodes. Provides operator sugar so expressions
    # can be written naturally.
    class Node
      def +(other)
        Add.new(self, other)
      end

      def -(other)
        Subtract.new(self, other)
      end

      def *(other)
        Multiply.new(self, other)
      end

      def /(other)
        Divide.new(self, other)
      end

      def **(exponent)
        Power.new(self, exponent)
      end

      # Time derivative of the given order (1 by default).
      def ddt(order = 1)
        TimeDerivative.new(self, order)
      end

      # Physical dimension of this node as a Unit with scalar 1.
      # @return [RubyUnits::Unit]
      def dimension
        raise NotImplementedError
      end

      # Numeric value of this node. Variables are looked up in +env+ by name,
      # time derivatives by +[name, order]+.
      def evaluate(env)
        raise NotImplementedError
      end

      # @return [Node] dimensionless counterpart of this node
      def nondim(context, restores)
        raise NotImplementedError
      end
    end

    # A numeric constant, optionally carrying a unit.
    class Constant < Node
      attr_reader :value, :unit

      # @param value [Numeric]
      # @param unit [RubyUnits::Unit, String, nil] nil for a dimensionless constant
      def initialize(value, unit = nil)
        super()
        @value = value
        @unit = unit.nil? || unit.is_a?(RubyUnits::Unit) ? unit : RubyUnits::Unit.new(unit)
      end

      def dimension
        return RubyUnits::Unit.new("1") unless unit

        base = unit.to_base
        base / base.scalar
      end

      def evaluate(_env)
        value
      end

      def nondim(context, _restores)
        Constant.new(value / context.scale_for(dimension))
      end

      def to_s
        unit ? "#{value} [#{unit.units}]" : value.to_s
      end
    end

    # A physical variable identified by name, with a declared dimension.
    class Variable < Node
      attr_reader :name

      # @param name [Symbol, String]
      # @param unit [RubyUnits::Unit, String]
      def initialize(name, unit)
        super()
        @name = name.to_sym
        @unit = unit.is_a?(RubyUnits::Unit) ? unit : RubyUnits::Unit.new(unit)
      end

      def dimension
        base = @unit.to_base
        base / base.scalar
      end

      def evaluate(env)
        env.fetch(name)
      end

      def nondim(context, restores)
        scale = context.scale_for(dimension)
        restores << Restore.new(:variable, name, 0, scale, dimension.to_base)
        DimensionlessVariable.new(name)
      end

      def to_s
        name.to_s
      end
    end

    # The dimensionless counterpart of a Variable (same name, no dimension).
    class DimensionlessVariable < Node
      attr_reader :name

      def initialize(name)
        super()
        @name = name.to_sym
      end

      def dimension
        RubyUnits::Unit.new("1")
      end

      def evaluate(env)
        env.fetch(name)
      end

      def nondim(_context, _restores)
        self
      end

      def to_s
        "#{name}_nd"
      end
    end

    # Addition/subtraction of two nodes with a dimension compatibility check.
    class BinaryOp < Node
      attr_reader :left, :right

      def initialize(left, right)
        super()
        @left = left
        @right = right
        check_dimensions! if dimension_check?
      end

      def dimension_check?
        false
      end

      def check_dimensions!
        return if left.dimension =~ right.dimension

        raise DimensionError,
              "incompatible dimensions in #{self.class.op_symbol}: #{left.dimension.units} vs #{right.dimension.units}"
      end

      def self.op_symbol
        name.split("::").last.downcase
      end

      def to_s
        "(#{left} #{self.class.op_symbol} #{right})"
      end
    end

    # Addition; both branches must share the same dimension.
    class Add < BinaryOp
      def dimension_check?
        true
      end

      def self.op_symbol
        "+"
      end

      def dimension
        left.dimension
      end

      def evaluate(env)
        left.evaluate(env) + right.evaluate(env)
      end

      def nondim(context, restores)
        Add.new(left.nondim(context, restores), right.nondim(context, restores))
      end
    end

    # Subtraction; both branches must share the same dimension.
    class Subtract < BinaryOp
      def dimension_check?
        true
      end

      def self.op_symbol
        "-"
      end

      def dimension
        left.dimension
      end

      def evaluate(env)
        left.evaluate(env) - right.evaluate(env)
      end

      def nondim(context, restores)
        Subtract.new(left.nondim(context, restores), right.nondim(context, restores))
      end
    end

    # Multiplication; dimensions combine.
    class Multiply < BinaryOp
      def self.op_symbol
        "*"
      end

      def dimension
        left.dimension * right.dimension
      end

      def evaluate(env)
        left.evaluate(env) * right.evaluate(env)
      end

      def nondim(context, restores)
        Multiply.new(left.nondim(context, restores), right.nondim(context, restores))
      end
    end

    # Division; dimensions combine.
    class Divide < BinaryOp
      def self.op_symbol
        "/"
      end

      def dimension
        left.dimension / right.dimension
      end

      def evaluate(env)
        left.evaluate(env) / right.evaluate(env)
      end

      def nondim(context, restores)
        Divide.new(left.nondim(context, restores), right.nondim(context, restores))
      end
    end

    # Integer power of a node.
    class Power < Node
      attr_reader :base, :exponent

      def initialize(base, exponent)
        super()
        raise ArgumentError, "only integer exponents are supported, got #{exponent.inspect}" unless exponent.is_a?(Integer)

        @base = base
        @exponent = exponent
      end

      def dimension
        base.dimension**exponent
      end

      def evaluate(env)
        base.evaluate(env)**exponent
      end

      def nondim(context, restores)
        Power.new(base.nondim(context, restores), exponent)
      end

      def to_s
        "(#{base})^#{exponent}"
      end
    end

    # Time derivative of the given order. The derivative of order n picks up a
    # factor of time_scale**n when moving to dimensionless time.
    class TimeDerivative < Node
      attr_reader :child, :order

      def initialize(child, order = 1)
        super()
        raise ArgumentError, "derivative order must be a positive Integer, got #{order.inspect}" unless order.is_a?(Integer) && order >= 1
        raise ArgumentError, "time derivatives apply to variables, got #{child.inspect}" unless child.respond_to?(:name)

        @child = child
        @order = order
      end

      def dimension
        child.dimension / (RubyUnits::Unit.new("s")**order)
      end

      def evaluate(env)
        env.fetch([child.name, order])
      end

      def nondim(context, restores)
        scale = context.scale_for(dimension)
        restores << Restore.new(:derivative, child.name, order, scale, dimension.to_base)
        DimensionlessTimeDerivative.new(child.nondim(context, restores), order)
      end

      def to_s
        "d#{order}(#{child})/dt#{order}"
      end
    end

    # Derivative with respect to the dimensionless time tau. Carries no
    # physical dimension beyond that of its (dimensionless) child.
    class DimensionlessTimeDerivative < TimeDerivative
      def dimension
        child.dimension
      end

      def nondim(_context, _restores)
        self
      end

      def to_s
        "d#{order}(#{child})/dtau#{order}"
      end
    end

    # One reverse-mapping entry: how to restore a physical value from its
    # dimensionless counterpart (+physical = dimensionless * factor+).
    Restore = Struct.new(:kind, :name, :order, :factor, :unit) do
      def to_s
        scale = (unit * factor).to_s
        case kind
        when :time
          "t = tau * #{scale}"
        when :variable
          "#{name} = #{name}_nd * #{scale}"
        when :derivative
          "d#{order}(#{name})/dt#{order} = d#{order}(#{name}_nd)/dtau#{order} * #{scale}"
        end
      end
    end

    # Reference scales supplied by the caller: one time scale plus one scale
    # per variable (a scale may also just pin down a base dimension such as
    # mass so constants with that dimension can be scaled).
    class Context
      attr_reader :time_scale, :scales

      # @param time_scale [RubyUnits::Unit, String] reference time, e.g. Unit("1 s")
      # @param scales [Hash{Symbol, String => RubyUnits::Unit, String}] reference scale per variable/dimension
      def initialize(time_scale:, scales: {})
        @time_scale = coerce_unit(time_scale)
        @scales = scales.transform_keys(&:to_sym).transform_values { coerce_unit(_1) }
        @dimension_scales = {}
        unless base_dimensions(@time_scale.to_base) == { "<second>" => 1 }
          raise ArgumentError, "time scale must be a pure time quantity, got #{@time_scale.to_base.inspect}"
        end
        register_dimension_scale!(@time_scale)
        @scales.each_value { register_dimension_scale!(_1) }
      end

      # Numeric scale factor (in base SI) for a dimension given as a Unit.
      # @return [Numeric] 1.0 for dimensionless quantities
      def scale_for(dimension)
        base_dimensions(dimension.to_base).reduce(1.0) do |factor, (base_unit, exponent)|
          scale = @dimension_scales[base_unit]
          raise DimensionError, "no reference scale registered for base dimension #{base_unit} (needed by #{dimension.units})" unless scale

          factor * (scale**exponent)
        end
      end

      # Rewrite +expression+ in dimensionless form.
      # @return [Result]
      def nondimensionalize(expression)
        restores = [Restore.new(:time, :t, 0, scale_for(self.class.time_dimension), self.class.time_dimension)]
        dimensionless = expression.nondim(self, restores)
        Result.new(expression: dimensionless, restores: restores.uniq, context: self)
      end

      # Dimension of time itself (scalar 1, seconds).
      def self.time_dimension
        RubyUnits::Unit.new("s")
      end

      private

      def coerce_unit(unit)
        unit.is_a?(RubyUnits::Unit) ? unit : RubyUnits::Unit.new(unit)
      end

      # Break a base Unit into {base_unit_name => exponent}, ignoring "<1>".
      def base_dimensions(base_unit)
        tally = Hash.new(0)
        base_unit.numerator.each { tally[_1] += 1 }
        base_unit.denominator.each { tally[_1] -= 1 }
        tally.delete("<1>")
        tally.delete("<each>")
        tally.reject { |_, exponent| exponent.zero? }
      end

      # Register a scale for a pure single base dimension (e.g. 0.1 m, 2 kg).
      # Scales with compound dimensions are kept as variable scales only.
      def register_dimension_scale!(unit)
        dims = base_dimensions(unit.to_base)
        return unless dims.size == 1 && dims.values.first == 1

        base_unit = dims.keys.first
        factor = unit.to_base.scalar
        existing = @dimension_scales[base_unit]
        if existing && (existing - factor).abs > 1e-12 * [existing.abs, factor.abs, 1.0].max
          raise ArgumentError, "conflicting reference scales for #{base_unit}: #{existing} vs #{factor}"
        end
        @dimension_scales[base_unit] = factor
      end
    end

    # The outcome of nondimensionalizing an expression: the dimensionless
    # expression tree plus the instructions needed to map dimensionless
    # results back to physical units.
    class Result
      attr_reader :expression, :restores, :context

      def initialize(expression:, restores:, context:)
        @expression = expression
        @restores = restores
        @context = context
      end

      # Human-readable reverse mapping instructions.
      # @return [Array<String>]
      def restore_instructions
        restores.map(&:to_s)
      end

      # Convert a dimensionless value back to physical units.
      # @param name [Symbol] variable name
      # @param value [Numeric] dimensionless value
      # @param order [Integer] time-derivative order (0 for the variable itself)
      # @return [Float] value in base SI units
      def to_physical(name, value, order: 0)
        value * factor_for(name, order)
      end

      # Convert a physical value (base SI) to its dimensionless counterpart.
      def to_dimensionless(name, value, order: 0)
        value / factor_for(name, order)
      end

      private

      def factor_for(name, order)
        restore = restores.find { _1.name == name.to_sym && _1.order == order && %i[variable derivative].include?(_1.kind) }
        raise KeyError, "no restore information for #{name} (order #{order})" unless restore

        restore.factor
      end
    end
  end
end
