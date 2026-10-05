# frozen_string_literal: true

RSpec.describe RubyUnits::BuckinghamPi do
  describe "Unit.buckingham_pi" do
    let(:variables) do
      [
        Unit.new("1 m/s^2"),
        Unit.new("2 m/s"),
        Unit.new("4 m")
      ]
    end

    it "builds independent dimensionless products with rational exponents" do
      result = Unit.buckingham_pi(variables, repeating: [1, 2])
      group = result.groups.first

      expect(result.dimension_matrix).to eq([[1, 1, 1], [-2, -1, 0]])
      expect(result.rank).to eq(2)
      expect(result.repeating_variables).to eq([variables[1], variables[2]])
      expect(result.non_repeating_indices).to eq([0])
      expect(result.groups.size).to eq(1)
      expect(group.exponents).to eq([Rational(1, 1), Rational(-2, 1), Rational(1, 1)])
      expect(group.product).to eq(Unit.new("1"))
      expect(group.product).to be_unitless
    end

    it "selects repeated variables by exact matrix rank" do
      result = Unit.buckingham_pi(variables)

      expect(result.repeating_indices).to eq([0, 1])
      expect(result.groups.first.exponents).to eq([Rational(1, 1), Rational(-2, 1), Rational(1, 1)])
    end

    it "preserves dimensionless values when measured in compatible units" do
      centimeter_variables = [
        Unit.new("100 cm/s^2"),
        Unit.new("200 cm/s"),
        Unit.new("400 cm")
      ]

      meter_result = Unit.buckingham_pi(variables, repeating: [1, 2])
      centimeter_result = Unit.buckingham_pi(centimeter_variables, repeating: [1, 2])

      expect(centimeter_result.groups.first.exponents).to eq(meter_result.groups.first.exponents)
      expect(centimeter_result.groups.first.product).to eq(meter_result.groups.first.product)
      expect(centimeter_result.groups.first.product.scalar).to eq(1)
    end

    it "returns fractional Rational exponents without using Float for rank analysis" do
      area = Unit.new("9 m^2")
      length = Unit.new("3 m")
      width = Unit.new("6 m")

      result = Unit.buckingham_pi([area, length, width], repeating: [0])

      expect(result.rank).to eq(1)
      expect(result.groups.map(&:exponents)).to eq([
        [Rational(-1, 2), Rational(1, 1), Rational(0, 1)],
        [Rational(-1, 2), Rational(0, 1), Rational(1, 1)]
      ])
      expect(result.groups.map { |group| group.product.scalar }).to eq([1, 2])
      expect(result.groups.flat_map(&:exponents)).to all(be_a(Rational))
    end

    it "explains why requested repeated variables are dependent" do
      expect {
        Unit.buckingham_pi(variables, repeating: [0, 1])
      }.not_to raise_error

      expect {
        Unit.buckingham_pi(variables, repeating: [0, 1, 2])
      }.to raise_error(
        ArgumentError,
        "2 dimensionally independent repeated variables are required, but 3 were supplied"
      )

      dependent_lengths = [
        Unit.new("1 m"),
        Unit.new("2 m"),
        Unit.new("1 s")
      ]

      expect {
        Unit.buckingham_pi(dependent_lengths, repeating: [0, 1])
      }.to raise_error(
        ArgumentError,
        "Repeated variables at indices [0, 1] are dimensionally dependent: their rank is 1, but 2 independent variables are required"
      )
    end

    it "rejects invalid repeated variable indices" do
      expect {
        Unit.buckingham_pi(variables, repeating: [1, 1])
      }.to raise_error(ArgumentError, "Repeated variable indices must be unique and within 0...3")

      expect {
        Unit.buckingham_pi(variables, repeating: [0, 3])
      }.to raise_error(ArgumentError, "Repeated variable indices must be unique and within 0...3")
    end

    it "accepts objects and strings that convert to units" do
      result = Unit.buckingham_pi(["1 m", Unit.new(2, "m"), "1 s"], repeating: [0, 2])

      expect(result.variables).to all(be_a(RubyUnits::Unit))
      expect(result.groups.first.exponents).to eq([Rational(-1, 1), Rational(1, 1), Rational(0, 1)])
      expect(result.groups.first.product.scalar).to eq(2)
    end

    it "rejects empty variable lists and objects that cannot convert to units" do
      expect { Unit.buckingham_pi([]) }.to raise_error(ArgumentError, "At least one variable is required")
      expect {
        RubyUnits::BuckinghamPi.analyze([Object.new])
      }.to raise_error(ArgumentError, "Variable at index 0 must respond to #to_unit")
    end

    it "returns no dimensionless groups for a complete dimensional basis" do
      result = Unit.buckingham_pi([Unit.new("1 m"), Unit.new("1 kg"), Unit.new("1 s")])

      expect(result.rank).to eq(3)
      expect(result.repeating_indices).to eq([0, 1, 2])
      expect(result.groups).to eq([])
    end
  end

  describe RubyUnits::BuckinghamPi::Result do
    it "represents supplied dimensionless variables as independent dimensionless groups" do
      result = RubyUnits::BuckinghamPi.analyze([Unit.new("2"), Unit.new("3")])

      expect(result.rank).to eq(0)
      expect(result.repeating_indices).to eq([])
      expect(result.groups.map(&:exponents)).to eq([
        [Rational(1, 1), Rational(0, 1)],
        [Rational(0, 1), Rational(1, 1)]
      ])
      expect(result.groups.map { |group| group.product.scalar }).to eq([2, 3])
    end
  end
end
