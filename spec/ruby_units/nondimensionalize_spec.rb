# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyUnits::Nondimensionalize do
  subject(:nd) { RubyUnits::Nondimensionalize }

  let(:x) { nd::Variable.new(:x, "m") }
  let(:mass) { nd::Constant.new(2.0, "kg") }
  let(:damping) { nd::Constant.new(0.5, "N*s/m") }
  let(:stiffness) { nd::Constant.new(10.0, "N/m") }

  # residual of the damped mass-spring equation: m x'' + c x' + k x
  let(:equation) { mass * x.ddt(2) + damping * x.ddt + stiffness * x }

  let(:context) do
    nd::Context.new(
      time_scale: RubyUnits::Unit.new("1 s"),
      scales: { x: RubyUnits::Unit.new("0.1 m"), m: RubyUnits::Unit.new("2 kg") }
    )
  end

  let(:result) { context.nondimensionalize(equation) }

  describe "expression nodes" do
    it "checks dimensions on every addition branch" do
      time = nd::Variable.new(:t, "s")
      expect { x + time }.to raise_error(nd::DimensionError, /incompatible dimensions/)
      expect { x - time }.to raise_error(nd::DimensionError, /incompatible dimensions/)
    end

    it "allows adding quantities with compatible but different units" do
      expect { x + nd::Variable.new(:y, "cm") }.not_to raise_error
    end

    it "only supports integer powers" do
      expect { x**2 }.not_to raise_error
      expect { x**2.5 }.to raise_error(ArgumentError, /integer/)
    end

    it "requires a positive integer derivative order" do
      expect { x.ddt(0) }.to raise_error(ArgumentError, /order/)
      expect { x.ddt(1.5) }.to raise_error(ArgumentError, /order/)
    end

    it "scales time derivatives by the time scale raised to the derivative order" do
      first = x.ddt.dimension
      second = x.ddt(2).dimension
      expect(first.units).to eq("m/s")
      expect(second.units).to eq("m/s^2")
    end
  end

  describe RubyUnits::Nondimensionalize::Context do
    it "rejects a non-time time scale" do
      expect { nd::Context.new(time_scale: RubyUnits::Unit.new("1 m")) }
        .to raise_error(ArgumentError, /time scale/)
    end

    it "rejects conflicting scales for the same base dimension" do
      expect do
        nd::Context.new(time_scale: RubyUnits::Unit.new("1 s"),
                        scales: { a: RubyUnits::Unit.new("0.1 m"), b: RubyUnits::Unit.new("0.2 m") })
      end.to raise_error(ArgumentError, /conflicting/)
    end

    it "raises when a constant needs a dimension without a registered scale" do
      no_mass = nd::Context.new(time_scale: RubyUnits::Unit.new("1 s"), scales: { x: RubyUnits::Unit.new("0.1 m") })
      expect { no_mass.nondimensionalize(equation) }.to raise_error(nd::DimensionError, /no reference scale/)
    end
  end

  describe "nondimensionalization of the damped mass-spring equation" do
    it "produces the expected dimensionless coefficients" do
      # m_hat x'' + c_hat x' + k_hat x with m_hat = 1, c_hat = 0.25, k_hat = 5
      expect(result.expression.evaluate(x: 0.0, [:x, 1] => 0.0, [:x, 2] => 1.0)).to be_within(1e-12).of(1.0)
      expect(result.expression.evaluate(x: 0.0, [:x, 1] => 1.0, [:x, 2] => 0.0)).to be_within(1e-12).of(0.25)
      expect(result.expression.evaluate(x: 1.0, [:x, 1] => 0.0, [:x, 2] => 0.0)).to be_within(1e-12).of(5.0)
    end

    it "returns reverse mapping instructions for variables, derivatives and time" do
      instructions = result.restore_instructions
      expect(instructions).to include("t = tau * 1 s")
      expect(instructions).to include("x = x_nd * 0.1 m")
      expect(instructions.any? { _1.include?("d2(x)/dt2") }).to be(true)
    end

    it "converts values back to physical units" do
      expect(result.to_physical(:x, 3.0)).to be_within(1e-12).of(0.3)
      expect(result.to_physical(:x, 3.0, order: 1)).to be_within(1e-12).of(0.3)
      expect(result.to_physical(:x, 3.0, order: 2)).to be_within(1e-12).of(0.3)
      expect(result.to_dimensionless(:x, 0.3)).to be_within(1e-12).of(3.0)
    end

    it "keeps residuals consistent when a trajectory is mapped back to original units" do
      # dimensionless coefficients read back through the public API
      m_hat = result.expression.evaluate(x: 0.0, [:x, 1] => 0.0, [:x, 2] => 1.0)
      c_hat = result.expression.evaluate(x: 0.0, [:x, 1] => 1.0, [:x, 2] => 0.0) - 0.0
      k_hat = result.expression.evaluate(x: 1.0, [:x, 1] => 0.0, [:x, 2] => 0.0)

      # integrate x_hat'' = -(c_hat x_hat' + k_hat x_hat) / m_hat with RK4
      dtau = 1.0e-4
      steps = 2000
      accel = ->(pos, vel) { -(c_hat * vel + k_hat * pos) / m_hat }
      trajectory = Array.new(steps + 1) # [tau, x_hat, v_hat]
      pos = 1.0
      vel = 0.0
      (0..steps).each do |i|
        trajectory[i] = [i * dtau, pos, vel]
        next if i == steps

        k1v = accel.call(pos, vel)
        k1x = vel
        k2v = accel.call(pos + 0.5 * dtau * k1x, vel + 0.5 * dtau * k1v)
        k2x = vel + 0.5 * dtau * k1v
        k3v = accel.call(pos + 0.5 * dtau * k2x, vel + 0.5 * dtau * k2v)
        k3x = vel + 0.5 * dtau * k2v
        k4v = accel.call(pos + dtau * k3x, vel + dtau * k3v)
        k4x = vel + dtau * k3v
        pos += dtau / 6.0 * (k1x + 2 * k2x + 2 * k3x + k4x)
        vel += dtau / 6.0 * (k1v + 2 * k2v + 2 * k3v + k4v)
      end

      equation_scale = context.scale_for(equation.dimension)
      expect(equation_scale).to be_within(1e-12).of(0.2) # kg*m/s^2

      # sample interior points; second derivative from a central difference
      [200, 500, 1000, 1500, 1800].each do |i|
        _tau, x_nd, v_nd = trajectory[i]
        a_nd = (trajectory[i + 1][2] - trajectory[i - 1][2]) / (2 * dtau)

        # residual in dimensionless form
        r_nd = result.expression.evaluate(x: x_nd, [:x, 1] => v_nd, [:x, 2] => a_nd)
        expect(r_nd.abs).to be < 1.0e-6

        # same trajectory mapped back to original units via the restore data
        env = {
          x: result.to_physical(:x, x_nd),
          [:x, 1] => result.to_physical(:x, v_nd, order: 1),
          [:x, 2] => result.to_physical(:x, a_nd, order: 2)
        }
        r_physical = equation.evaluate(env)

        expect(r_physical).to be_within(1e-9).of(equation_scale * r_nd)
        expect(r_physical.abs).to be < 1.0e-6 * equation_scale * 10
      end
    end
  end
end
