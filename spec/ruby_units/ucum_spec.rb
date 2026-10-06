# frozen_string_literal: true

require "yaml"

RSpec.describe RubyUnits::Ucum do
  let(:sample_path) { File.expand_path("../fixtures/ucum_samples.yml", __dir__) }
  let(:samples) { YAML.load_file(sample_path).fetch("samples") }

  describe ".parse" do
    it "returns an Expression bound to a Unit" do
      expression = described_class.parse("m/s2")

      expect(expression).to be_a(described_class::Expression)
      expect(expression.unit).to eq(RubyUnits::Unit.new("1 m/s^2"))
    end

    it "supports multiplication, division, and signed exponents" do
      expect(described_class.load("g.m-2")).to eq(RubyUnits::Unit.new("1 g/m^2"))
      expect(described_class.load("m.s-2")).to eq(RubyUnits::Unit.new("1 m/s^2"))
      expect(described_class.load("1/s")).to eq(RubyUnits::Unit.new("1 1/s"))
    end

    it "supports decimal prefixes and explicit 10^n factors" do
      expect(described_class.load("km")).to eq(RubyUnits::Unit.new("1 km"))
      expect(described_class.load("10^3Pa")).to eq(RubyUnits::Unit.new("1000 Pa"))
      expect(described_class.load("10^-3m")).to eq(RubyUnits::Unit.new("1/1000 m"))
      expect(described_class.load("daN")).to eq(RubyUnits::Unit.new("10 N"))
    end

    it "supports parentheses and square brackets for grouping" do
      expect(described_class.load("(m/s)2")).to eq(RubyUnits::Unit.new("1 m^2/s^2"))
      expect(described_class.load("[m/s]2")).to eq(described_class.load("m2/s2"))
    end

    it "applies signed and nested group exponents" do
      expect(described_class.load("(m/s)-2")).to eq(RubyUnits::Unit.new("1 s^2/m^2"))
      expect(described_class.load("(km)-1")).to eq(RubyUnits::Unit.new("1 1/km"))
      expect(described_class.load("((m/s)2)3")).to eq(RubyUnits::Unit.new("1 m^6/s^6"))
    end

    it "supports nested annotations and preserves bracket style on the tree" do
      expect(described_class.parse("m{note {nested}}").to_ucum).to eq("m{note {nested}}")
      expect(described_class.parse("[m/s]{x}").to_ucum).to eq("[m/s]{x}")
    end

    it "accepts both liter codes but canonicalizes to lowercase l" do
      expect(described_class.dump(described_class.load("L"))).to eq("l")
      expect(described_class.dump(described_class.load("l"))).to eq("l")
    end

    it "keeps annotations available on the expression tree" do
      expression = described_class.parse("m{patient height}")

      expect(expression.to_ucum).to eq("m{patient height}")
      expect(described_class.dump(expression.unit)).to eq("m")
    end

    it "is strictly case sensitive" do
      expect { described_class.parse("M") }.to raise_error(described_class::ParseError)
      expect { described_class.parse("KG") }.to raise_error(described_class::ParseError)
      expect { described_class.parse("meter") }.to raise_error(described_class::ParseError)
    end

    it "rejects whitespace, malformed groups, and trailing operators" do
      expect { described_class.parse("m / s") }.to raise_error(described_class::ParseError)
      expect { described_class.parse("m/") }.to raise_error(described_class::ParseError)
      expect { described_class.parse("(m") }.to raise_error(described_class::ParseError)
      expect { described_class.parse("m{s") }.to raise_error(described_class::ParseError)
    end

    it "reports precise parse error positions" do
      expect do
        described_class.parse("m.M")
      end.to raise_error(described_class::ParseError) { |error| expect(error.position).to eq(2) }
    end
  end

  describe "offset (affine) units" do
    it "parses Celsius as a non-proportional temperature scale" do
      expression = described_class.parse("Cel")

      expect(expression.unit.units).to eq("tempC")
      expect(expression.to_unit(100).convert_to(described_class.load("K"))).to eq(RubyUnits::Unit.new("373.15 tempK"))
    end

    it "converts Celsius readings through the expression helper" do
      expect(described_class.parse("Cel").convert(100, "K")).to eq(RubyUnits::Unit.new("373.15 tempK"))
      expect(described_class.parse("Cel").convert(0, "K")).to eq(RubyUnits::Unit.new("273.15 tempK"))
    end

    it "refuses to multiply, divide, or exponentiate the offset unit" do
      %w[Cel/s 1.Cel m.Cel Cel2 (Cel) Cel-1 1/Cel].each do |code|
        expect { described_class.parse(code) }.to raise_error(described_class::OffsetUnitError)
      end
    end

    it "reports the source position of the offset unit inside a product" do
      code = "m.Cel"
      expect do
        described_class.parse(code)
      end.to raise_error(described_class::OffsetUnitError) { |error| expect(error.position).to eq(code.index("Cel")) }
    end
  end

  describe "special functions" do
    it "reports the unsupported function name and exact position" do
      code = "10.[pH]"
      expect do
        described_class.parse(code)
      end.to raise_error(described_class::UnsupportedSpecialError) do |error|
        expect(error.function).to eq("ph")
        expect(error.position).to eq(code.index("[pH]"))
      end
    end

    it "recognizes bracketed temperature special functions" do
      expect { described_class.parse("[degF]") }
        .to raise_error(described_class::UnsupportedSpecialError) { |error| expect(error.function).to eq("fdeg") }
    end
  end

  describe ".dump" do
    {
      "m" => "m",
      "m/s2" => "m/s2",
      "m.s-2" => "m/s2",
      "kg/m3" => "kg/m3",
      "kPa" => "kPa",
      "10^3Pa" => "kPa",
      "100.m" => "hm",
      "(m/s)2" => "m2/s2",
      "N.m" => "N.m",
      "100" => "10^2",
      "1/min" => "1/min"
    }.each do |input, canonical|
      it "canonicalizes #{input.inspect} to #{canonical.inspect}" do
        expect(described_class.dump(described_class.load(input))).to eq(canonical)
      end
    end

    it "serializes Celsius as Cel" do
      expect(described_class.dump(described_class.load("Cel"))).to eq("Cel")
    end

    it "keeps percent meaning through a numeric factor re-output" do
      canonical = described_class.dump(described_class.load("%"))
      expect(canonical).to eq("1/10^2")
      expect(described_class.load(canonical)).to eq(described_class.load("%"))
    end
  end

  describe "Unit integration" do
    it "adds a strict UCUM class entry point" do
      expect(RubyUnits::Unit.ucum("km")).to eq(RubyUnits::Unit.new("1 km"))
    end

    it "adds a UCUM output method" do
      expect(RubyUnits::Unit.new("1 km/s").to_ucum).to eq("km/s")
    end

    it "keeps the permissive string parser lenient" do
      expect(RubyUnits::Unit.new("1 meter/second^2")).to be_a(RubyUnits::Unit)
      expect { described_class.parse("meter/second^2") }.to raise_error(described_class::ParseError)
    end
  end

  describe "standard sample set" do
    it "reads in, converts, and re-emits every sample without changing its meaning" do
      samples.reject { |sample| sample["affine"] }.each do |sample|
        expression = described_class.parse(sample.fetch("code"))
        unit = expression.unit

        expected = RubyUnits::Unit.new(sample.fetch("base"))
        expect(unit.to_base).to be_within(RubyUnits::Unit.new("1e-9 #{base_tolerance_unit(expected)}"))
          .of(expected.to_base)

        canonical = described_class.dump(unit)
        expect(canonical).to eq(sample.fetch("canonical"))
        expect(described_class.load(canonical).to_base).to be_within(RubyUnits::Unit.new("1e-9 #{base_tolerance_unit(expected)}"))
          .of(expected.to_base)

        if sample["annotated"]
          expect(expression.to_ucum).to eq(sample["annotated"])
        end
      end
    end

    it "round trips the affine Celsius sample with the offset intact" do
      sample = samples.find { |entry| entry["affine"] && entry["target"] }
      result = described_class.parse(sample["code"]).convert(sample["value"], sample["target"])

      expect(result.scalar.to_f).to be_within(1e-9).of(sample["target_value"])
      target_unit = RubyUnits::Unit.new(
        scalar: 1,
        numerator: result.numerator,
        denominator: result.denominator
      )
      expect(described_class.dump(target_unit)).to eq(sample["target"])
    end

    def base_tolerance_unit(unit)
      unit.unitless? ? "" : unit.to_base.units
    end
  end
end
