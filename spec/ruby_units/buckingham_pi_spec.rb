# frozen_string_literal: true

RSpec.describe "Buckingham Pi analysis" do
  it "exposes an integer dimensional vector" do
    vector = Unit.new("1 N").to_base.dimensional_vector

    expect(vector).to eq([1, -2, 0, 1, 0, 0, 0, 0, 0, 0])
    expect(vector.map(&:class)).to all(eq(Integer))
  end

  let(:reynolds_variables) do
    [
      Unit.new("1000 kg/m^3"),
      Unit.new("2 m/s"),
      Unit.new("3 m"),
      Unit.new("1/1000 Pa*s")
    ]
  end

  it "returns independent dimensionless groups with exact rational or integer exponents" do
    groups = Unit.buckingham_pi(reynolds_variables)

    expect(groups.size).to eq(1)
    expect(groups.first[:exponents]).to eq(0 => 1, 1 => 1, 2 => 1, 3 => -1)
    expect(groups.first[:exponents].values.map(&:class)).to all(eq(Integer))
    expect(groups.first[:product]).to be_unitless
    expect(groups.first[:product].scalar).to eq(Rational(6_000_000))
    expect(groups.first[:value]).to eq(Rational(6_000_000))
  end

  it "accepts named repeating variables" do
    variables = {
      rho: reynolds_variables[0],
      velocity: reynolds_variables[1],
      length: reynolds_variables[2],
      viscosity: reynolds_variables[3]
    }

    groups = Unit.buckingham_pi(variables, repeating_variables: %i[velocity length viscosity])

    expect(groups.size).to eq(1)
    expect(groups.first[:exponents]).to eq(rho: 1, velocity: 1, length: 1, viscosity: -1)
  end

  it "preserves Hash variable keys and accepts string or symbol references" do
    variables = {
      "rho" => reynolds_variables[0],
      "velocity" => reynolds_variables[1],
      "length" => reynolds_variables[2],
      "viscosity" => reynolds_variables[3]
    }

    groups = Unit.buckingham_pi(variables, repeating_variables: %i[velocity length viscosity])

    expect(groups.first[:exponents]).to eq(
      "rho" => 1,
      "velocity" => 1,
      "length" => 1,
      "viscosity" => -1
    )
  end

  it "has an explicit analysis alias" do
    expect(Unit.buckingham_pi_analysis(reynolds_variables)).to eq(Unit.buckingham_pi(reynolds_variables))
  end

  it "accepts indexed repeating variables" do
    groups = Unit.buckingham_pi(reynolds_variables, repeating_variables: [1, 2, 3])

    expect(groups.first[:exponents]).to eq(0 => 1, 1 => 1, 2 => 1, 3 => -1)
  end

  it "accepts the shorter repeating keyword" do
    groups = Unit.buckingham_pi(reynolds_variables, repeating: [1, 2, 3])

    expect(groups.first[:exponents]).to eq(0 => 1, 1 => 1, 2 => 1, 3 => -1)
  end

  it "accepts repeating variable objects" do
    groups = Unit.buckingham_pi(reynolds_variables, reynolds_variables.values_at(1, 2, 3))

    expect(groups.first[:exponents]).to eq(0 => 1, 1 => 1, 2 => 1, 3 => -1)
  end

  it "keeps the dimensionless value invariant after correct unit conversion" do
    metric_groups = Unit.buckingham_pi(reynolds_variables)
    centimeter_variables = [
      reynolds_variables[0],
      Unit.new("200 cm/s"),
      Unit.new("300 cm"),
      reynolds_variables[3]
    ]
    centimeter_groups = Unit.buckingham_pi(centimeter_variables, [1, 2, 3])

    expect(centimeter_groups.first[:product]).to eq(metric_groups.first[:product])
  end

  it "preserves rational exponents" do
    groups = Unit.buckingham_pi([Unit.new("4 m^2"), Unit.new("1 m^3")])

    expect(groups.size).to eq(1)
    expect(groups.first[:exponents]).to eq(0 => Rational(3, 2), 1 => -1)
    expect(groups.first[:product]).to be_unitless
    expect(groups.first[:value]).to eq(Rational(8))
  end

  it "returns no groups when all variables are dimensionally independent" do
    expect(Unit.buckingham_pi([Unit.new("1 m"), Unit.new("1 s")])).to eq([])
  end

  it "includes already dimensionless variables as Pi groups" do
    groups = Unit.buckingham_pi([Unit.new("1 m"), Unit.new("2")])

    expect(groups.first[:exponents]).to eq(0 => 0, 1 => 1)
    expect(groups.first[:product].scalar).to eq(2)
  end

  it "explains dependent repeating variables" do
    variables = [Unit.new("1 m"), Unit.new("100 cm"), Unit.new("1 s"), Unit.new("1 m/s")]

    expect { Unit.buckingham_pi(variables, [0, 1, 2]) }
      .to raise_error(ArgumentError, /dimensionally dependent.*rank 2.*3 independent repeating variables/)
  end

  it "explains repeating variables whose count matches rank but are dependent" do
    variables = [Unit.new("1 m"), Unit.new("100 cm"), Unit.new("1 s"), Unit.new("1 m/s")]

    expect { Unit.buckingham_pi(variables, [0, 1]) }
      .to raise_error(ArgumentError, /dimensionally dependent.*rank 1.*2 independent repeating variables/)
  end

  it "explains repeating variables that do not span the full dimensional space" do
    variables = [Unit.new("1 m"), Unit.new("100 cm"), Unit.new("1 s"), Unit.new("1 m/s")]

    message = /do not span the dimensional space.*rank 2.*only 1 repeating variable was supplied/
    expect { Unit.buckingham_pi(variables, [0]) }.to raise_error(ArgumentError, message)
  end

  it "rejects repeating variables that were not supplied" do
    expect { Unit.buckingham_pi(reynolds_variables, [:length]) }
      .to raise_error(ArgumentError, "Repeating variable :length is not one of the supplied variables")
  end
end
