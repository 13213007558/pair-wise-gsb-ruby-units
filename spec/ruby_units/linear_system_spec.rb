# frozen_string_literal: true

RSpec.describe RubyUnits::LinearSystem do
  let(:unit) { RubyUnits::Unit }

  describe ".solve" do
    it "is available on Unit and through matrix-solve aliases" do
      result = unit.matrix_solve([[unit.new("1 N/m")]], [unit.new("2 N")], %w[m])

      expect(result.x).to eq([unit.new("2 m")])
      expect(unit.solve_matrix([[unit.new("1 N/m")]], [unit.new("2 N")], %w[m]).x).to eq(result.x)
    end

    it "solves mixed length, angle, force, and torque equations with units" do
      coefficients = [
        [unit.new("1 N/m"), unit.new("1 N/rad")],
        [unit.new("0 N"), unit.new("1 N*m/rad")]
      ]
      constants = [unit.new("10 N"), unit.new("5 N*m")]

      result = described_class.solve(coefficients, constants, %w[m rad])

      expect(result.x).to eq([unit.new("5 m"), unit.new("5 rad")])
      expect(result.residuals).to eq([unit.new("0 N"), unit.new("0 N*m")])
    end

    it "supports array-style access to unknowns and residuals" do
      result = described_class.solve(
        [[unit.new("1 N/m")]],
        [unit.new("2 N")],
        %w[m]
      )

      expect(result[:x]).to eq([unit.new("2 m")])
      expect(result[0]).to eq([unit.new("2 m")])
      expect(result).to contain_exactly([unit.new("2 m")], [unit.new("0 N")])
    end

    it "uses the dimensional part of a target unit even when it has a scalar" do
      coefficients = [
        [unit.new("1 N/m"), unit.new("1 N/rad")],
        [unit.new("0 N"), unit.new("1 N*m/rad")]
      ]
      constants = [unit.new("10 N"), unit.new("5 N*m")]

      result = described_class.solve(coefficients, constants, [unit.new("1000 mm"), unit.new("1 rad")])

      expect(result.x).to eq([unit.new("5000 mm"), unit.new("5 rad")])
    end

    it "preserves declared zero b units in residuals" do
      coefficients = [
        [unit.new("2 N/m"), unit.new("0 N/rad")],
        [unit.new("0 N/m"), unit.new("1 N/rad")]
      ]
      constants = [unit.new("0 N"), unit.new("3 N")]

      result = described_class.solve(coefficients, constants, %w[m rad])

      expect(result.x).to eq([unit.new("0 m"), unit.new("3 rad")])
      expect(result.residuals.map(&:units)).to eq(%w[N N])
    end

    it "returns equivalent results for meter/newton and millimeter/kilonewton inputs" do
      si_coefficients = [
        [unit.new("100 N/m"), unit.new("50 N/rad")],
        [unit.new("200 N"), unit.new("25 N*m/rad")]
      ]
      si_constants = [unit.new("7 N"), unit.new("13/2 N*m")]
      metric_coefficients = [
        [unit.new("1/10000 kN/mm"), unit.new("1/20 kN/rad")],
        [unit.new("1/5 kN"), unit.new("25 kN*mm/rad")]
      ]
      metric_constants = [unit.new("7/1000 kN"), unit.new("13/2 kN*mm")]

      si_result = described_class.solve(si_coefficients, si_constants, %w[m rad])
      metric_result = described_class.solve(metric_coefficients, metric_constants, %w[mm rad])

      expect(si_result.x).to eq([unit.new("1/50 m"), unit.new("1/10 rad")])
      expect(metric_result.x).to eq([unit.new("20 mm"), unit.new("1/10 rad")])
      expect(metric_result.x.first.convert_to("m").base_scalar).to eq(si_result.x.first.base_scalar)
      expect(si_result.residuals).to eq([unit.new("0 N"), unit.new("0 N*m")])
      expect(metric_result.residuals).to eq([unit.new("0 kN"), unit.new("0 kN*mm")])
    end

    it "keeps tiny floating point residuals in the units of each row" do
      coefficients = [
        [unit.new("0.0001 kN/mm"), unit.new("0.05 kN/rad")],
        [unit.new("0.2 kN"), unit.new("25 kN*mm/rad")]
      ]
      constants = [unit.new("0.007 kN"), unit.new("6.5 kN*mm")]

      result = described_class.solve(coefficients, constants, %w[mm rad])

      expect(result.x.first.base_scalar).to be_within(1e-9).of(unit.new("20 mm").base_scalar)
      expect(result.x.last.base_scalar).to be_within(1e-12).of(unit.new("0.1 rad").base_scalar)
      expect(result.residuals.map(&:units)).to eq(%w[kN kN*mm])
      expect(result.residuals.map { |residual| residual.base_scalar.abs }).to all(be < 1e-9)
    end

    it "uses the declared unit of a zero coefficient during dimensional checking" do
      coefficients = [
        [unit.new("0 N/rad"), unit.new("1 N/rad")],
        [unit.new("1 N*m/rad"), unit.new("0 N*m/m")]
      ]
      constants = [unit.new("1 N"), unit.new("2 N*m")]

      expect {
        described_class.solve(coefficients, constants, %w[m rad])
      }.to raise_error(ArgumentError, /A\[0,0\].*N\/rad.*x\[0\].*m.*b\[0\].*N/)
    end

    it "rejects numeric zero because its missing unit cannot be inferred later" do
      coefficients = [
        [0, unit.new("1 N/rad")],
        [unit.new("1 N*m/m"), unit.new("1 N*m/rad")]
      ]
      constants = [unit.new("1 N"), unit.new("2 N*m")]

      expect {
        described_class.solve(coefficients, constants, %w[m rad])
      }.to raise_error(ArgumentError, "A[0,0] must be a RubyUnits::Unit; numeric zero carries no unit information")
    end

    it "diagnoses a singular system separately from a contradictory row" do
      coefficients = [
        [unit.new("1 N/m"), unit.new("0 N/rad")],
        [unit.new("1 N/m"), unit.new("0 N/rad")]
      ]
      constants = [unit.new("1 N"), unit.new("1 N")]

      expect {
        described_class.solve(coefficients, constants, %w[m rad])
      }.to raise_error(described_class::SingularSystemError, "the coefficient matrix is singular")
    end

    it "diagnoses singularity when a later column is missing from every remaining row" do
      coefficients = [
        [unit.new("1 N/m"), unit.new("0 N/rad")],
        [unit.new("0 N/m"), unit.new("0 N/rad")]
      ]
      constants = [unit.new("1 N"), unit.new("0 N")]

      expect {
        described_class.solve(coefficients, constants, %w[m rad])
      }.to raise_error(described_class::SingularSystemError, "the coefficient matrix is singular")
    end

    it "diagnoses an inconsistent row in an otherwise dimensionally valid system" do
      coefficients = [
        [unit.new("1 N/m"), unit.new("0 N/rad")],
        [unit.new("1 N/m"), unit.new("0 N/rad")]
      ]
      constants = [unit.new("1 N"), unit.new("2 N")]

      expect {
        described_class.solve(coefficients, constants, %w[m rad])
      }.to raise_error(described_class::InconsistentSystemError, "the linear system is inconsistent")
    end

    it "rejects shapes before attempting dimensional solving" do
      expect {
        described_class.solve([[unit.new("1 N/m")]], [unit.new("1 N"), unit.new("2 N")], %w[m])
      }.to raise_error(ArgumentError, "b must have one entry per row")
    end
  end
end
