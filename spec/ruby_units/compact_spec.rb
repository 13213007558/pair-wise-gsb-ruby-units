# frozen_string_literal: true

RSpec.describe RubyUnits::Unit::CompactResult do
  subject(:result) { RubyUnits::Unit.new("5.6 kg*m/s^2").compact(%w[N J Pa kg m s]) }

  it "exposes the compacted unit" do
    expect(result.unit).to eq(RubyUnits::Unit.new("5.6 N"))
  end

  it "reports the total display cost" do
    expect(result.cost).to eq(1)
  end

  it "reports the chosen terms" do
    expect(result.terms).to eq("N" => 1)
  end

  it { is_expected.to be_covered }

  context "when the candidates cannot represent the unit" do
    subject(:result) { RubyUnits::Unit.new("5 A").compact(%w[N kg m s]) }

    it { is_expected.not_to be_covered }

    it "keeps the original representation" do
      expect(result.unit).to eq(RubyUnits::Unit.new("5 A"))
      expect(result.unit.units).to eq("A")
    end

    it "explains the uncovered dimensions" do
      expect(result.uncovered_dimensions).to eq([:current])
    end
  end
end

RSpec.describe "Unit#compact" do
  let(:candidates) { %w[N J Pa kg m s] }

  describe "choosing the cheapest representation" do
    it "compacts a derived unit to a single named unit" do
      expect(RubyUnits::Unit.new("5.6 kg*m/s^2").compact(candidates).unit).to eq(RubyUnits::Unit.new("5.6 N"))
    end

    it "compacts energy to joules" do
      expect(RubyUnits::Unit.new("2 kg*m^2/s^2").compact(candidates).unit).to eq(RubyUnits::Unit.new("2 J"))
    end

    it "compacts pressure to pascals" do
      expect(RubyUnits::Unit.new("3 kg/m*s^2").compact(candidates).unit).to eq(RubyUnits::Unit.new("3 Pa"))
    end

    it "uses numerator and denominator candidates" do
      result = RubyUnits::Unit.new("1.2 kg/m^3").compact(%w[kg m], max_exponent: 3)
      expect(result.unit).to eq(RubyUnits::Unit.new("1.2 kg/m^3"))
      expect(result.terms).to eq("kg" => 1, "m" => -3)
    end

    it "respects caller supplied display costs" do
      result = RubyUnits::Unit.new("5.6 kg*m/s^2").compact("N" => 5, "kg" => 1, "m" => 1, "s" => 1)
      expect(result.unit.units).to eq("kg*m/s^2")
      expect(result.cost).to eq(4)
    end

    it "accepts a Hash of candidates as a single argument" do
      result = RubyUnits::Unit.new("5.6 kg*m/s^2").compact({ "N" => 5, "kg" => 1, "m" => 1, "s" => 1 })
      expect(result.cost).to eq(4)
    end

    it "accepts Unit instances as candidates" do
      result = RubyUnits::Unit.new("5.6 kg*m/s^2").compact([RubyUnits::Unit.new("N"), "kg", "m", "s"])
      expect(result.unit).to eq(RubyUnits::Unit.new("5.6 N"))
    end

    it "ignores dimensionless candidates" do
      result = RubyUnits::Unit.new("5 m").compact(["1", "m"])
      expect(result.unit).to eq(RubyUnits::Unit.new("5 m"))
      expect(result.terms).to eq("m" => 1)
    end

    it "returns unitless units unchanged" do
      result = RubyUnits::Unit.new("5").compact(candidates)
      expect(result).to be_covered
      expect(result.unit).to eq(RubyUnits::Unit.new("5"))
      expect(result.cost).to eq(0)
    end
  end

  describe "exact scale folding" do
    it "keeps Integer scalars exact" do
      result = RubyUnits::Unit.new("56 kg*m/s^2").compact(candidates)
      expect(result.unit.scalar).to eq(56)
      expect(result.unit.scalar).to be_an(Integer)
    end

    it "keeps Rational scalars exact" do
      result = RubyUnits::Unit.new("1/3 J").compact(%w[N m])
      expect(result.unit.scalar).to eq(Rational(1, 3))
      expect(result.unit.units).to eq("N*m")
    end

    it "folds candidate scales into the scalar" do
      result = RubyUnits::Unit.new("5 cm").compact(%w[m])
      expect(result.unit.scalar).to eq(Rational(1, 20))
    end

    it "preserves Float scalars" do
      result = RubyUnits::Unit.new("5.6 kg*m/s^2").compact(candidates)
      expect(result.unit.scalar).to eq(5.6)
      expect(result.unit.scalar).to be_a(Float)
    end

    it "round-trips exactly through the original units" do
      ["5.6 kg*m/s^2", "1/3 J", "56 kg/m*s^2", "7 m/s", "11 kg/m^3", "13 1/s"].each do |string|
        unit = RubyUnits::Unit.new(string)
        compacted = unit.compact(%w[N J Pa kg m s])
        expect(compacted).to be_covered
        expect(compacted.unit.convert_to(unit.units)).to eq(unit)
      end
    end
  end

  describe "bounded search" do
    it "does not try exponents beyond max_exponent" do
      result = RubyUnits::Unit.new("1 m^3").compact(%w[m], max_exponent: 2)
      expect(result).not_to be_covered
    end

    it "finds representations within max_exponent" do
      result = RubyUnits::Unit.new("1 m^3").compact(%w[m], max_exponent: 3)
      expect(result).to be_covered
      expect(result.terms).to eq("m" => 3)
    end

    it "rejects a non-positive max_exponent" do
      expect { RubyUnits::Unit.new("1 m").compact(%w[m], max_exponent: 0) }.to raise_error(ArgumentError)
      expect { RubyUnits::Unit.new("1 m").compact(%w[m], max_exponent: 2.5) }.to raise_error(ArgumentError)
    end
  end

  describe "linearly dependent candidates" do
    it "prefers fewer unit symbols at equal cost" do
      result = RubyUnits::Unit.new("1 J").compact("J" => 2, "N" => 1, "m" => 1)
      expect(result.terms).to eq("J" => 1)
    end

    it "breaks full ties deterministically in favor of earlier candidates" do
      expect(RubyUnits::Unit.new("1 J").compact(["J", "N*m"]).terms).to eq("J" => 1)
      expect(RubyUnits::Unit.new("1 J").compact(["N*m", "J"]).terms).to eq("N*m" => 1)
    end

    it "is stable across repeated calls" do
      unit = RubyUnits::Unit.new("3 kg*m^2/s^2")
      first = unit.compact(candidates)
      5.times do
        repeated = unit.compact(candidates)
        expect(repeated.terms).to eq(first.terms)
        expect(repeated.cost).to eq(first.cost)
      end
    end
  end

  describe "dimensionless units with semantic markers" do
    it "does not drop angles" do
      result = RubyUnits::Unit.new("2 rad/s").compact(%w[s])
      expect(result).not_to be_covered
      expect(result.uncovered_dimensions).to eq([:angle])
      expect(result.unit).to eq(RubyUnits::Unit.new("2 rad/s"))
    end

    it "covers angles when a matching candidate is available" do
      result = RubyUnits::Unit.new("2 rad/s").compact(%w[rad s])
      expect(result).to be_covered
      expect(result.unit).to eq(RubyUnits::Unit.new("2 rad/s"))
    end

    it "does not treat radians as dimensionless" do
      result = RubyUnits::Unit.new("1 rad").compact(["1"])
      expect(result).not_to be_covered
      expect(result.uncovered_dimensions).to eq([:angle])
    end
  end

  describe "validation" do
    it "rejects temperature units" do
      expect { RubyUnits::Unit.new("37 tempC").compact(%w[tempK]) }.to raise_error(ArgumentError, /temperature/i)
    end

    it "rejects temperature candidates" do
      expect { RubyUnits::Unit.new("5 kelvin").compact(%w[tempC kelvin]) }.to raise_error(ArgumentError, /temperature/i)
    end

    it "rejects negative display costs" do
      expect { RubyUnits::Unit.new("5 m").compact("m" => -1) }.to raise_error(ArgumentError, /cost/)
    end

    it "rejects empty candidates" do
      expect { RubyUnits::Unit.new("5 m").compact([]) }.to raise_error(ArgumentError, /empty/)
      expect { RubyUnits::Unit.new("5 m").compact }.to raise_error(ArgumentError, /candidate/)
    end

    it "rejects mixing argument and keyword candidates" do
      expect { RubyUnits::Unit.new("5 m").compact(%w[m], "s" => 1) }.to raise_error(ArgumentError)
    end
  end

  describe "exhaustive verification against the candidate table" do
    # candidate table: derived SI units plus the base units they are made of
    table = { "N" => 1, "J" => 1, "Pa" => 1, "kg" => 1, "m" => 1, "s" => 1 }
    max_exponent = 2

    # independently enumerate every exponent combination and return
    # [cost, terms] of the cheapest exact representation, or nil
    def brute_force_best(target_vector, entries, max_exponent)
      best = nil
      ranges = entries.map { (-max_exponent..max_exponent).to_a }
      ranges.first.product(*ranges.drop(1)) do |exponents|
        vector = ::Array.new(target_vector.size, 0)
        entries.each_with_index do |entry, index|
          entry[:vector].each_with_index { |component, dim| vector[dim] += component * exponents[index] }
        end
        next unless vector == target_vector

        cost = entries.each_with_index.sum { |entry, index| entry[:cost] * exponents[index].abs }
        terms = exponents.sum(&:abs)
        best = [cost, terms] if best.nil? || cost < best[0] || (cost == best[0] && terms < best[1])
      end
      best
    end

    entries = table.map do |name, cost|
      unit = RubyUnits::Unit.new(name)
      { cost:, vector: unit.send(:unit_signature_vector) }
    end

    [
      "3 kg*m/s^2",     # force
      "7 kg*m^2/s^2",   # energy
      "11 kg/m*s^2",    # pressure
      "13 kg*m^2/s^3",  # power
      "17 m/s",         # speed
      "19 m/s^2",       # acceleration
      "23 kg/m^3",      # density
      "29 1/s",         # frequency
      "31 kg*m/s",      # momentum
      "37 kg^2*m/s^4"   # not representable with this table
    ].each do |string|
      context "with #{string}" do
        subject(:unit) { RubyUnits::Unit.new(string) }

        it "matches the exhaustively determined optimum" do
          result = unit.compact(table, max_exponent:)
          best = brute_force_best(unit.send(:unit_signature_vector), entries, max_exponent)
          if best.nil?
            expect(result).not_to be_covered
          else
            expect(result).to be_covered
            expect([result.cost, result.terms.values.sum(&:abs)]).to eq(best)
          end
        end

        it "converts back to the original value exactly" do
          result = unit.compact(table, max_exponent:)
          expect(result.unit.convert_to(unit.units)).to eq(unit)
        end
      end
    end
  end
end
