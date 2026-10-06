RSpec.describe RubyUnits::Unit, "#compact" do
  let(:candidates) do
    {
      "N" => 1,
      "J" => 1,
      "Pa" => 1,
      "kg" => 3,
      "m" => 3,
      "s" => 3
    }
  end

  it "selects the lowest-cost force representation and converts the scalar exactly" do
    result = RubyUnits::Unit.new("12 kg*m/s^2").compact(candidates)

    expect(result).to be_complete
    expect(result.unit.to_s).to eq("12 N")
    expect(result.cost).to eq(1)
    expect(result.exponents).to eq("N" => 1)
  end

  it "selects energy and pressure derived units exactly" do
    energy = RubyUnits::Unit.new("7 kg*m^2/s^2").compact(candidates)
    pressure = RubyUnits::Unit.new("5 kg/m*s^2").compact(candidates)

    expect(energy.unit.to_s).to eq("7 J")
    expect(pressure.unit.to_s).to eq("5 Pa")
  end

  it "round-trips through the original SI representation" do
    {
      "12 kg*m/s^2" => "12 kg*m/s^2",
      "7 kg*m^2/s^2" => "7 kg*m^2/s^2",
      "5 kg/m*s^2" => "5 kg/m*s^2"
    }.each do |original, original_units|
      unit = RubyUnits::Unit.new(original)
      compacted = unit.compact(candidates).unit

      expect(compacted.convert_to(original_units)).to eq(unit)
    end
  end

  it "keeps a base representation when it has the lower display cost" do
    result = RubyUnits::Unit.new("3 kg*m/s^2").compact(
      candidates.except("N", "J", "Pa").merge("kg" => 1, "m" => 1, "s" => 1)
    )

    expect(result.unit.units).to eq("kg*m/s^2")
    expect(result.cost).to eq(4)
  end

  it "chooses the same tied representation regardless of insertion order" do
    cheap_candidates = {
      "N" => 1,
      "kg" => 1,
      "m" => 1,
      "s" => 1
    }
    reordered = cheap_candidates.to_a.rotate(2).to_h

    first = RubyUnits::Unit.new("1 kg*m/s^2").compact(cheap_candidates)
    second = RubyUnits::Unit.new("1 kg*m/s^2").compact(reordered)

    expect(first.exponents).to eq(second.exponents)
    expect(first.unit.units).to eq(second.unit.units)
  end

  it "preserves angle dimensions when angular units are not offered" do
    result = RubyUnits::Unit.new("2 rad").compact({ "kg" => 1 })

    expect(result).not_to be_complete
    expect(result.unit).to eq(RubyUnits::Unit.new("2 rad"))
    expect(result.uncovered_dimensions).to eq(["angle^1"])
    expect(result.reason).to include("angle^1")
  end

  it "uses an angle candidate when one is available" do
    result = RubyUnits::Unit.new("180 deg").compact({ "rad" => 1 })

    expect(result).to be_complete
    expect(result.unit.scalar).to be_within(1e-15).of(Math::PI)
    expect(result.unit.units).to eq("rad")
    expect(result.unit.convert_to("deg")).to eq(RubyUnits::Unit.new("180 deg"))
  end

  it "converts through prefixed candidates with the exact scalar ratio" do
    result = RubyUnits::Unit.new("1000 kg*m/s^2").compact({ "kN" => 1, "N" => 2 })

    expect(result.unit).to eq(RubyUnits::Unit.new("1 kN"))
    expect(result.exponents).to eq("kN" => 1)
    expect(result.unit.convert_to("kg*m/s^2")).to eq(RubyUnits::Unit.new("1000 kg*m/s^2"))
  end

  it "supports differential temperature units without using temperature offsets" do
    result = RubyUnits::Unit.new("10 degC").compact({ "degK" => 1 })

    expect(result.unit).to eq(RubyUnits::Unit.new("10 degK"))
    expect(result.unit.convert_to("degC")).to eq(RubyUnits::Unit.new("10 degC"))
  end

  it "does not replace an angular unit with a unitless counting unit" do
    result = RubyUnits::Unit.new("1 rad").compact({ "each" => 0, "rad" => 10 })

    expect(result.unit.units).to eq("rad")
    expect(result.exponents).to eq("rad" => 1)
  end

  it "returns the original unit when dimensions are only representable outside the exponent bound" do
    source = RubyUnits::Unit.new("1 m^4")
    result = source.compact({ "m" => 1 }, max_exponent: 3)

    expect(result).not_to be_complete
    expect(result.unit).to eq(source)
    expect(result.uncovered_dimensions).to eq([])
    expect(result.reason).to include("-3", "3")
  end

  it "rejects absolute temperatures because they use offsets rather than linear scaling" do
    expect { RubyUnits::Unit.new("300 tempK").compact({ "tempK" => 1 }) }
      .to raise_error(ArgumentError, /linear unit scaling/)
  end

  it "rejects invalid candidate shapes and exponent bounds" do
    expect { RubyUnits::Unit.new("1 m").compact([["m"]]) }
      .to raise_error(ArgumentError, /\[unit, cost\] pairs/)
    expect { RubyUnits::Unit.new("1 m").compact({ "m" => 1 }, max_exponent: 0) }
      .to raise_error(ArgumentError, /positive Integer/)
  end

  it "matches an exhaustive search of every bounded N, J, Pa, kg, m, s combination" do
    candidate_names = candidates.keys
    normalized_candidates = RubyUnits::Unit.new(1).send(:normalize_compact_candidates, candidates)
    search_states = RubyUnits::Unit.new(1).send(
      :compact_search_states,
      normalized_candidates.first[:vector].size,
      normalized_candidates,
      2
    )
    candidate_vectors = normalized_candidates.map { |candidate| candidate[:vector] }
    costs = normalized_candidates.map { |candidate| candidate[:cost] }
    bounded_choices = [-2, -1, 0, 1, 2]
    expected_states = {}

    bounded_choices.repeated_permutation(candidate_names.size) do |exponents|
      target = vector_from_exponents(exponents, candidate_vectors)
      key = [
        exponents.each_with_index.sum { |value, index| value.abs * costs[index] },
        exponents.count(&:nonzero?),
        exponents,
        exponents.map(&:abs)
      ]
      current = expected_states[target]
      expected_states[target] = key if current.nil? || compact_key_less_than?(key, current)
    end

    expected_states.each do |target, expected|
      actual = search_states.fetch(target)[:exponents].map(&:last)
      actual_key = [
        actual.each_with_index.sum { |value, index| value.abs * costs[index] },
        actual.count(&:nonzero?),
        actual,
        actual.map(&:abs)
      ]
      expect(actual_key).to eq(expected)
    end
  end

  it "round-trips representative derived and inverse combinations" do
    normalized_candidates = RubyUnits::Unit.new(1).send(:normalize_compact_candidates, candidates)
    candidate_vectors = normalized_candidates.map { |candidate| candidate[:vector] }
    representative_targets = [
      [1, 0, 0, 0, 0, 0],
      [0, 1, 0, 0, 0, 0],
      [0, 0, 1, 0, 0, 0],
      [0, 0, 0, 1, 1, -2],
      [0, 0, 0, 1, 2, -2],
      [0, 0, 0, 1, -1, -2],
      [-1, 1, 0, 0, 1, 0],
      [1, 0, -1, 0, 2, 0],
      [-1, 0, 1, 0, -2, 0]
    ].map { |exponents| vector_from_exponents(exponents, candidate_vectors) }

    representative_targets.uniq.reject { |target| target.all?(&:zero?) }.each do |target|
      original = base_unit_from_vector(target, -17)
      result = original.compact(candidates, max_exponent: 2)

      expect(result).to be_complete
      expect(result.unit.convert_to(original.units)).to eq(original)
    end
  end

  def compact_key_less_than?(left, right)
    left.zip(right).each do |left_value, right_value|
      next if left_value == right_value

      return compact_key_less_than?(left_value, right_value) if left_value.is_a?(Array)

      return left_value < right_value
    end
    false
  end

  def vector_from_exponents(exponents, vectors)
    ::Array.new(vectors.first.size, 0).tap do |target|
      exponents.each_with_index do |exponent, index|
        vectors[index].each_with_index do |value, dimension_index|
          target[dimension_index] += exponent * value
        end
      end
    end
  end

  def base_unit_from_vector(vector, scalar)
    dimensions = %w[length mass time]
    base_units = { "length" => "m", "mass" => "kg", "time" => "s" }
    names = RubyUnits::Unit.new(1).send(:compact_dimension_names)
    unit = RubyUnits::Unit.new(scalar)

    dimensions.each do |dimension|
      exponent = vector[names.index(dimension)]
      unit = unit * (RubyUnits::Unit.new(base_units[dimension])**exponent) unless exponent.zero?
    end
    unit
  end
end
