# frozen_string_literal: true

require "spec_helper"

describe RubyUnits::Nondimensional do
  let(:x) { described_class.variable(:x) }
  let(:m) { described_class.variable(:m) }
  let(:c) { described_class.variable(:c) }
  let(:k) { described_class.variable(:k) }
  let(:dimensions) do
    {
      x: { length: 1 },
      m: { mass: 1 },
      c: { mass: 1, time: -1 },
      k: { mass: 1, time: -2 }
    }
  end
  let(:scales) { { x: 2, m: 2, c: Rational(1, 2), k: 4 } }
  let(:equation) { m * x.ddt(2) + c * x.ddt + k * x }
  let(:result) do
    described_class.transform(equation, dimensions: dimensions, scales: scales, time_scale: 3)
  end

  describe "expression construction" do
    it "builds arithmetic expressions without evaluating strings" do
      expression = (x + described_class.number(1)) * described_class.number(2) - x / x
      expect(expression.to_s).to eq "(((x + 1) * 2) - (x / x))"
    end

    it "provides short constructors on the module" do
      expect(described_class.var(:x)).to eq x
      expect(described_class.num(2)).to eq described_class.number(2)
    end

    it "accepts positive and negative integer powers" do
      expect((x**2).exponent).to eq 2
      expect((x**-1).exponent).to eq(-1)
    end

    it "rejects non-integer powers" do
      expect { x**1.5 }.to raise_error(ArgumentError, /integer/)
    end

    it "rejects non-positive derivative orders" do
      expect { x.ddt(0) }.to raise_error(ArgumentError, /positive integer/)
    end

    it "rejects non-expression operands without evaluating them" do
      expect { x + 1 }.to raise_error(ArgumentError, /Expression/)
      expect { described_class.number(1) * "2" }.to raise_error(ArgumentError, /Expression/)
    end
  end

  describe ".transform" do
    it "checks every addition branch before transforming" do
      bad_equation = m * x.ddt(2) + x
      expect do
        described_class.transform(bad_equation, dimensions: dimensions, scales: scales, time_scale: 3)
      end.to raise_error(described_class::DimensionMismatch, /dimensions/)
    end

    it "checks nested addition branches" do
      bad_equation = (m * x.ddt(2) + c * x.ddt) + x * x
      expect do
        described_class.transform(bad_equation, dimensions: dimensions, scales: scales, time_scale: 3)
      end.to raise_error(described_class::DimensionMismatch)
    end

    it "checks right-nested subtraction branches and uses the first branch scale" do
      bad_equation = m * x.ddt(2) - (c * x.ddt - x * x)
      expect do
        described_class.transform(bad_equation, dimensions: dimensions, scales: scales, time_scale: 3)
      end.to raise_error(described_class::DimensionMismatch)

      right_nested = m * x.ddt(2) - (c * x.ddt - k * x)
      right_nested_result = described_class.transform(
        right_nested,
        dimensions: dimensions,
        scales: scales,
        time_scale: 3
      )
      expect(right_nested_result.scale).to eq Rational(4, 9)
    end

    it "uses one time scale factor per derivative order" do
      expect(result.scale).to eq Rational(4, 9)
      expect(result.dimensions).to eq(mass: 1, length: 1, time: -2)
      expect(result.expression.to_s).to include("3/4")
      expect(result.expression.to_s).to include("18/1")
    end

    it "supports an explicit time variable and custom time name" do
      time = described_class.variable(:s)
      equation = x + time * x.ddt(time_name: :s)
      custom_result = described_class.transform(
        equation,
        dimensions: { x: { length: 1 } },
        scales: { x: 2 },
        time_scale: 5,
        time_name: :s
      )
      expect(custom_result.expression.to_s).to eq "(x_hat + (tau * d^1(x_hat)/dtau^1))"
      expect(custom_result.restoration.time.original).to eq :s
    end

    it "scales integer powers from the base scale" do
      power_result = described_class.transform(
        x**-2,
        dimensions: { x: { length: 1 } },
        scales: { x: 2 },
        time_scale: 3
      )
      expect(power_result.scale).to eq Rational(1, 4)
      expect(power_result.expression).to eq(RubyUnits::Nondimensional::Variable.new(:x_hat)**-2)
    end

    it "requires dimensions for every variable" do
      expect do
        described_class.transform(x, dimensions: {}, scales: { x: 1 }, time_scale: 1)
      end.to raise_error(described_class::MissingScale, /dimensions/)
    end

    it "requires positive reference scales" do
      expect do
        described_class.transform(x, dimensions: dimensions, scales: { x: 0 }, time_scale: 3)
      end.to raise_error(described_class::InvalidScale, /positive/)
    end

    it "validates the input expression and dimension mapping" do
      expect { described_class.transform(1, dimensions: {}, scales: {}, time_scale: 1) }
        .to raise_error(ArgumentError, /Expression/)
      expect { described_class.transform(x, dimensions: { x: { length: 1.5 } }, scales: { x: 1 }, time_scale: 1) }
        .to raise_error(ArgumentError, /integer/)
    end
  end

  describe "restoration" do
    it "describes variables, derivatives and the root residual scale" do
      expect(result.restoration.description).to include("t = 3 tau")
      expect(result.restoration.description).to include("x = 2 x_hat")
      expect(result.restoration.description).to include("d^2(x)/dt^2 = 2/9")
      expect(result.restoration.description).to include("original residual = 4/9 dimensionless residual")
    end
  end

  describe "damped mass-spring residual" do
    let(:times) { [0.1, 0.4, 0.9, 1.3] }

    it "agrees after mapping one trajectory back to original units" do
      times.each do |time|
        original_values = trajectory_at(time)
        dimensionless_values = dimensionless_trajectory_at(time / 3)
        original_residual = equation.evaluate(original_values[:variables], derivatives: original_values[:derivatives])
        dimensionless_residual = result.expression.evaluate(
          dimensionless_values[:variables],
          derivatives: dimensionless_values[:derivatives]
        )
        restored_residual = dimensionless_residual * result.scale

        expect(restored_residual).to be_within(1e-12).of(original_residual)
      end
    end
  end

  private

  def trajectory_at(time)
    displacement = Math.sin(1.7 * time) + 0.5 * Math.cos(0.9 * time)
    velocity = 1.7 * Math.cos(1.7 * time) - 0.45 * Math.sin(0.9 * time)
    acceleration = -2.89 * Math.sin(1.7 * time) - 0.405 * Math.cos(0.9 * time)
    {
      variables: { x: displacement, m: 2, c: 0.4, k: 6.25 },
      derivatives: { x: { 1 => velocity, 2 => acceleration } }
    }
  end

  def dimensionless_trajectory_at(tau)
    time = 3 * tau
    displacement = Math.sin(1.7 * time) + 0.5 * Math.cos(0.9 * time)
    velocity_dtau = 3 * (1.7 * Math.cos(1.7 * time) - 0.45 * Math.sin(0.9 * time))
    acceleration_dtau = 9 * (-2.89 * Math.sin(1.7 * time) - 0.405 * Math.cos(0.9 * time))
    {
      variables: { x_hat: displacement / 2, m_hat: 1, c_hat: Rational(4, 5), k_hat: Rational(25, 16) },
      derivatives: { x_hat: { 1 => velocity_dtau / 2, 2 => acceleration_dtau / 2 } }
    }
  end
end
