# frozen_string_literal: true

RSpec.describe RubyUnits::QuantityMatrix do
  describe ".solve" do
    it "solves equivalent force and moment inputs after independent row and column scaling" do
      si_a = [
        [Unit.new(2000, "N/m"), Unit.new(2, "N/rad")],
        [Unit.new(1000, "N*m/m"), Unit.new(4, "N*m/rad")]
      ]
      si_b = [Unit.new(6, "N"), Unit.new(9, "N*m")]

      si_solution = described_class.solve(si_a, si_b, target_units: [Unit.new(1, "m"), Unit.new(1, "rad")])

      expect(si_solution.unknowns).to eq([Unit.new(Rational(1, 1000), "m"), Unit.new(2, "rad")])
      expect(si_solution.residuals).to eq([Unit.new(0, "N"), Unit.new(0, "N*m")])

      millimetre_kilonewton_a = [
        [Unit.new(Rational(1, 500), "kN/mm"), Unit.new(Rational(1, 500), "kN/rad")],
        [Unit.new(Rational(1, 1000), "kN*m/mm"), Unit.new(Rational(1, 250), "kN*m/rad")]
      ]
      millimetre_kilonewton_b = [Unit.new(Rational(3, 500), "kN"), Unit.new(Rational(9, 1000), "kN*m")]

      scaled_solution = described_class.solve(
        millimetre_kilonewton_a,
        millimetre_kilonewton_b,
        target_units: [Unit.new(1, "mm"), Unit.new(1, "rad")]
      )

      expect(scaled_solution.unknowns).to eq([Unit.new(1, "mm"), Unit.new(2, "rad")])
      expect(scaled_solution[0].convert_to("m")).to eq(si_solution[0])
      expect(scaled_solution[1]).to eq(si_solution[1])
      expect(scaled_solution.residuals).to eq([Unit.new(0, "kN"), Unit.new(0, "kN*m")])
    end

    it "accepts declared units on zero coefficients and keeps row-specific residual units" do
      a = [
        [Unit.new(1, "N/m"), Unit.new(0, "N/rad")],
        [Unit.new(0, "N*m/m"), Unit.new(2, "N*m/rad")]
      ]
      b = [Unit.new(3, "N"), Unit.new(8, "N*m")]

      solution = described_class.solve(a, b, target_units: %w[m rad])

      expect(solution.x).to eq([Unit.new(3, "m"), Unit.new(4, "rad")])
      expect(solution.residuals).to eq([Unit.new(0, "N"), Unit.new(0, "N*m")])
    end

    it "supports dimensionless unknowns and dimensionless rows" do
      a = [[Unit.new(2), Unit.new(1)], [Unit.new(1), Unit.new(3)]]
      b = [Unit.new(4), Unit.new(9)]

      solution = described_class.solve(a, b, target_units: [Unit.new(1), Unit.new(1)])

      expect(solution.x).to eq([Unit.new(Rational(3, 5)), Unit.new(Rational(14, 5))])
      expect(solution.residuals).to eq([Unit.new(0), Unit.new(0)])
    end

    it "preserves the declared unit on a zero right-hand-side residual" do
      a = [[Unit.new(2, "N*m/rad"), Unit.new(1, "N*m")], [Unit.new(1, "N*m/rad"), Unit.new(1, "N*m")]]
      b = [Unit.new(0, "N*m"), Unit.new(1, "N*m")]

      solution = described_class.solve(a, b, target_units: ["rad", Unit.new(1)])

      expect(solution.x).to eq([Unit.new(-1, "rad"), Unit.new(2)])
      expect(solution.residuals).to eq([Unit.new(0, "N*m"), Unit.new(0, "N*m")])
    end

    it "raises a specific error when a bare zero coefficient has no unit" do
      a = [[Unit.new(1, "N/m"), 0], [Unit.new(1, "N*m/m"), Unit.new(1, "N*m/rad")]]
      b = [Unit.new(1, "N"), Unit.new(1, "N*m")]

      expect { described_class.solve(a, b, target_units: %w[m rad]) }
        .to raise_error(described_class::MissingUnitError, /A\[0, 1\].*zero but has no unit/)
    end

    it "uses the declared unit on a zero coefficient when checking dimensions" do
      a = [[Unit.new(1, "N/m"), Unit.new(0, "N")], [Unit.new(1, "N*m/m"), Unit.new(1, "N*m/rad")]]
      b = [Unit.new(1, "N"), Unit.new(1, "N*m")]

      expect { described_class.solve(a, b, target_units: %w[m rad]) }
        .to raise_error(described_class::IncompatibleUnitsError, /row 0.*"N".*"rad".*"N"/)
    end

    it "raises a specific error for a singular system" do
      a = [[Unit.new(1), Unit.new(0)], [Unit.new(0), Unit.new(0)]]
      b = [Unit.new(1), Unit.new(0)]

      expect { described_class.solve(a, b, target_units: [Unit.new(1), Unit.new(1)]) }
        .to raise_error(described_class::SingularMatrixError, "matrix is singular; no unique solution exists")
    end

    it "validates matrix and target vector shapes" do
      a = [[Unit.new(1), Unit.new(0)]]
      b = [Unit.new(1)]

      expect { described_class.solve(a, b, target_units: [Unit.new(1)]) }
        .to raise_error(described_class::ShapeError, "A must be square")
    end
  end
end
