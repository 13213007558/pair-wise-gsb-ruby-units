# frozen_string_literal: true

require "yaml"

RSpec.describe RubyUnits::Ucum do
  describe ".parse" do
    it "parses a simple proportional unit" do
      expression = described_class.parse("m")
      expect(expression.unit).to eq(RubyUnits::Unit.new("1 m"))
      expect(expression.to_ucum).to eq("m")
      expect(expression).not_to be_affine
    end

    it "applies decimal prefixes" do
      expect(described_class.parse("mm").unit).to eq(RubyUnits::Unit.new("1 mm"))
      expect(described_class.parse("kg").unit).to eq(RubyUnits::Unit.new("1 kg"))
      expect(described_class.parse("um").unit).to eq(RubyUnits::Unit.new("1 um"))
      expect(described_class.parse("daL").unit).to eq(RubyUnits::Unit.new("1 daL"))
    end

    it "treats prefixes as case sensitive" do
      expect(described_class.parse("mm").unit).to eq(RubyUnits::Unit.new("1 mm"))
      expect(described_class.parse("Mm").unit).to eq(RubyUnits::Unit.new("1 Mm"))
      expect { described_class.parse("MM") }.to raise_error(described_class::ParseError, /position 0/)
      expect { described_class.parse("Km") }.to raise_error(described_class::ParseError, /position 0/)
    end

    it "parses exponents with and without a caret" do
      expect(described_class.parse("m^2").unit).to eq(RubyUnits::Unit.new("1 m^2"))
      expect(described_class.parse("m2").unit).to eq(RubyUnits::Unit.new("1 m^2"))
      expect(described_class.parse("s-1").unit).to eq(RubyUnits::Unit.new("1 1/s"))
      expect(described_class.parse("kg.m.s-2").unit).to eq(RubyUnits::Unit.new("1 kg*m/s^2"))
    end

    it "parses products and quotients" do
      expect(described_class.parse("mg/L").unit).to eq(RubyUnits::Unit.new("1 mg/L"))
      expect(described_class.parse("kg.m/s2").unit).to eq(RubyUnits::Unit.new("1 kg*m/s^2"))
      group = described_class.parse("kJ/(mol.K)")
      expect(group.unit).to eq(described_class.parse("kJ/mol.K").unit)
      expect(group.unit).to eq(described_class.parse("kJ.mol-1.K-1").unit)
    end

    it "parses parentheses" do
      expression = described_class.parse("(kg.m)/(s2)")
      expect(expression.unit).to eq(RubyUnits::Unit.new("1 kg*m/s^2"))
      expect(expression.to_ucum).to eq("(kg.m)/(s2)")
    end

    it "parses a parenthesized exponent" do
      expression = described_class.parse("(m/s)2")
      expect(expression.unit).to eq(RubyUnits::Unit.new("1 m^2/s^2"))
      expect(expression.to_ucum).to eq("(m/s)2")
    end

    it "parses bare numeric factors" do
      expect(described_class.parse("100.m").unit).to eq(RubyUnits::Unit.new("100 m"))
      expect(described_class.parse("10/min").unit).to eq(RubyUnits::Unit.new("10 1/min"))
      expect(described_class.parse("10.5m").unit).to eq(RubyUnits::Unit.new("10.5 m"))
      expect(described_class.parse("1e3m").unit).to eq(RubyUnits::Unit.new("1000 m"))
    end

    it "allows an annotation before the exponent" do
      expect(described_class.parse("m{s}2").unit).to eq(RubyUnits::Unit.new("1 m^2"))
      expect(described_class.parse("m{s}2").to_ucum).to eq("m2{s}")
    end

    it "requires an exponent after a caret" do
      expect { described_class.parse("m^") }.to raise_error(described_class::ParseError, /expected an exponent/)
    end

    it "preserves component and expression annotations" do
      expect(described_class.parse("Cel{cells}").to_ucum).to eq("Cel{cells}")
      expect(described_class.parse("mg{Lipid}/L").to_ucum).to eq("mg{Lipid}/L")
      expect(described_class.parse("mg/L{report}").to_ucum).to eq("mg/L{report}")
    end

    it "parses common bracketed units" do
      expect(described_class.parse("[lbf]").unit).to eq(RubyUnits::Unit.new("1 lbf"))
      expect(described_class.parse("[in_i]").unit).to eq(RubyUnits::Unit.new("1 in"))
      expect(described_class.parse("[degF]").unit).to eq(RubyUnits::Unit.new("1 degF"))
    end

    it "keeps the lenient Unit parser unaffected" do
      expect(RubyUnits::Unit.new("1 kPa*s")).to eq(RubyUnits::Unit.new("1000 Pa*s"))
      # full unit names and spaces stay accepted by the lenient parser
      expect(RubyUnits::Unit.new("1 meter").to_s).to include("m")
      # the strict UCUM parser remains case sensitive
      expect { described_class.parse("meter") }.to raise_error(described_class::ParseError)
    end
  end

  describe "affine temperatures" do
    it "parses Cel and [degF] as affine point temperatures" do
      expect(described_class.parse("Cel")).to be_affine
      expect(described_class.parse("[degF]")).to be_affine
    end

    {
      "Cel/s"   => 0,
      "Cel.m"   => 0,
      "Cel2"    => 0,
      "1/Cel"   => 2,
      "(Cel)"   => 1,
      "(Cel)/s" => 1,
      "[degF]/s" => 0
    }.each do |code, position|
      it "rejects '#{code}' and reports position #{position}" do
        expect { described_class.parse(code) }
          .to raise_error(described_class::ParseError, /affine unit.*position #{position}/) do |error|
          expect(error.position).to eq(position)
        end
      end
    end

    it "performs affine value conversion" do
      expect(described_class.convert(0, "Cel", "[degF]")).to be_within(1e-9).of(32)
      expect(described_class.convert(100, "Cel", "[degF]")).to be_within(1e-9).of(212)
      expect(described_class.convert(32, "[degF]", "Cel")).to be_within(1e-9).of(0)
    end

    it "refuses point to proportional conversion" do
      expect { described_class.convert(0, "Cel", "K") }
        .to raise_error(described_class::ParseError, /cannot convert between point temperature/)
      expect { described_class.convert(1, "K", "Cel") }
        .to raise_error(described_class::ParseError, /cannot convert between point temperature/)
    end
  end

  describe "special units" do
    {
      "[pH]"  => [0, "log10"],
      "10[pH]" => [2, "log10"],
      "[Np]"  => [0, "ln"],
      "[bd]"  => [0, "2*log10"]
    }.each do |code, (position, function)|
      it "reports the unsupported function for '#{code}'" do
        expect { described_class.parse(code) }
          .to raise_error(described_class::ParseError, /#{Regexp.escape(function)}.*position #{position}/) do |error|
          expect(error.position).to eq(position)
        end
      end
    end
  end

  describe "syntax errors" do
    {
      ""     => "empty",
      "m//s" => "expected a unit",
      "m/"   => "expected a unit",
      "(m"   => /expected '\)'/,
      "m)"   => "unexpected character",
      "m{"   => "unterminated",
      "xyz"  => "unknown UCUM unit code"
    }.each do |code, message|
      it "rejects #{code.inspect}" do
        matcher = message.is_a?(Regexp) ? message : /#{message}/
        expect { described_class.parse(code) }.to raise_error(described_class::ParseError, matcher)
      end
    end

    it "requires a String" do
      expect { described_class.parse(nil) }.to raise_error(described_class::ParseError, /must be a String/)
      expect { described_class.parse(42) }.to raise_error(described_class::ParseError, /must be a String/)
    end
  end

  describe ".convert" do
    it "converts proportional values" do
      expect(described_class.convert(1, "km", "m")).to eq(1000)
      expect(described_class.convert(1, "mg/L", "g/L")).to eq(Rational(1, 1000))
      expect(described_class.convert(1, "m2", "cm2")).to eq(10_000)
    end
  end

  describe ".dump and Unit#to_ucum" do
    it "emits canonical UCUM for parsed expressions" do
      expect(described_class.dump(described_class.parse("mg/L"))).to eq("mg/L")
    end

    it "emits UCUM for ordinary RubyUnits::Unit objects" do
      expect(RubyUnits::Unit.new("1 mg/L").to_ucum).to eq("mg/l")
      expect(RubyUnits::Unit.new("1 kPa").to_ucum).to eq("kPa")
      expect(RubyUnits::Unit.new("1 mm/s^2").to_ucum).to eq("mm/s2")
      expect(RubyUnits::Unit.new("1 lbf/in^2").to_ucum).to eq("[lbf]/[in_i]2")
      expect(RubyUnits::Unit.new("1 1/min").to_ucum).to eq("1/min")
      expect(RubyUnits::Unit.new("1 tempC").to_ucum).to eq("Cel")
    end

    it "raises for units outside the UCUM subset" do
      expect { RubyUnits::Unit.new("1 fortnight").to_ucum }
        .to raise_error(ArgumentError, /cannot be represented as a UCUM code/)
    end
  end

  describe "standard samples" do
    samples = YAML.safe_load_file(File.expand_path("ucum_samples.yml", __dir__))["samples"]

    samples.each do |sample|
      code = sample["code"]

      it "reads '#{code}' with the expected proportional meaning" do
        expression = described_class.parse(code)
        if expression.affine?
          expect(expression.unit).to eq(RubyUnits::Unit.new("1 #{sample['base'].split.last}"))
        else
          expect(expression.unit).to eq(RubyUnits::Unit.new(sample["base"]))
        end
      end

      it "re-emits '#{code}' canonically and preserves meaning" do
        expression = described_class.parse(code)
        expect(expression.to_ucum).to eq(code)
        reparsed = described_class.parse(expression.to_ucum)
        if expression.affine?
          expect(expression.unit.convert_to("degK").scalar)
            .to eq(reparsed.unit.convert_to("degK").scalar)
        else
          expect(expression.unit).to eq(reparsed.unit)
        end
      end

      it "converts '#{code}' to '#{sample['convert_to']}'" do
        result = described_class.convert(sample["value"], code, sample["convert_to"])
        expected = sample["result"]
        if expected.is_a?(Float)
          expect(result).to be_within(1e-9).of(expected)
        else
          expect(result).to eq(expected)
        end
      end
    end
  end
end
