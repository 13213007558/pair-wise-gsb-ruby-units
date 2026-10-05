# frozen_string_literal: true

RSpec.describe RubyUnits::Measurement do
  subject(:measurement) { described_class.new("1.20 m") }

  describe ".new" do
    it "counts significant figures from the input literal" do
      expect(described_class.new("1.20 m").sig_figs).to eq(3)
      expect(described_class.new("1.2 m").sig_figs).to eq(2)
      expect(described_class.new("0.0500 kg").sig_figs).to eq(3)
      expect(described_class.new("1200 m").sig_figs).to eq(2)
      expect(described_class.new("1.20e3 m").sig_figs).to eq(3)
    end

    it "does not treat 1.20 m and 1.2 m as the same precision" do
      expect(described_class.new("1.20 m").to_s).to eq("1.20 m")
      expect(described_class.new("1.2 m").to_s).to eq("1.2 m")
    end

    it "accepts an explicit sig_figs override" do
      expect(described_class.new("1.2 m", sig_figs: 4).sig_figs).to eq(4)
    end

    it "treats rational literals as exact" do
      expect(described_class.new("1/2 m")).to be_exact
    end

    it "accepts a Unit and infers significant figures from its scalar" do
      expect(described_class.new(RubyUnits::Unit.new("1.2 m")).sig_figs).to eq(2)
    end
  end

  describe ".exact" do
    it "marks the value as an exact constant" do
      exact = described_class.exact("12 in")
      expect(exact).to be_exact
      expect(exact.sig_figs).to eq(described_class::EXACT)
    end

    it "displays exact values without significant figure rounding" do
      expect(described_class.exact("12 in").to_s).to eq("12 in")
    end
  end

  describe "#to_s" do
    it "preserves trailing zeros of the input precision" do
      expect(measurement.to_s).to eq("1.20 m")
    end

    it "can convert before formatting" do
      expect(measurement.to_s("cm")).to eq("120 cm")
    end

    it "rounds only for display, keeping the internal value unrounded" do
      converted = measurement.convert_to("ft")
      expect(converted.scalar).to be_within(1e-12).of(3.937007874015748)
      expect(converted.to_s).to eq("3.94 ft")
    end
  end

  describe "#quantize" do
    it "returns a measurement with a rounded internal value" do
      quantized = measurement.convert_to("ft").quantize
      expect(quantized.scalar).to eq(3.94)
      expect(quantized.to_s).to eq("3.94 ft")
    end

    it "leaves exact measurements untouched" do
      exact = described_class.exact("12 in")
      expect(exact.quantize).to equal(exact)
    end
  end

  describe "unit conversion" do
    it "preserves significant figures" do
      expect(measurement.convert_to("cm").sig_figs).to eq(3)
      expect(measurement.convert_to("cm").to_s).to eq("120 cm")
    end

    it "keeps the unrounded internal value" do
      expect(measurement.convert_to("ft").scalar).to be_within(1e-12).of(3.937007874015748)
    end

    it "converts inches to centimeters with the exact 2.54 factor" do
      expect(described_class.new("1.20 in").convert_to("cm").to_s).to eq("3.05 cm")
    end
  end

  describe "addition and subtraction (decimal place rule)" do
    it "keeps the decimal places of the least precise operand" do
      sum = described_class.new("1.20 m") + described_class.new("0.006 m")
      expect(sum.to_s).to eq("1.21 m")
    end

    it "compares decimal places in a common unit" do
      sum = described_class.new("1.20 m") + described_class.new("30.0 cm")
      expect(sum.scalar).to be_within(1e-12).of(1.5)
      expect(sum.to_s).to eq("1.50 m")
    end

    it "applies the same rule to subtraction" do
      difference = described_class.new("1.20 m") - described_class.new("1.15 m")
      expect(difference.to_s).to eq("0.05 m")
    end

    it "handles zero results" do
      difference = described_class.new("1.20 m") - described_class.new("1.2 m")
      expect(difference.to_s).to eq("0.0 m")
    end

    it "lets exact values keep the other operand's precision" do
      sum = described_class.exact("1 m") + described_class.new("1.20 m")
      expect(sum.to_s).to eq("2.20 m")
    end
  end

  describe "multiplication and division (significant figure rule)" do
    it "keeps the significant figures of the least precise operand" do
      area = described_class.new("1.20 m") * described_class.new("0.35 m")
      expect(area.sig_figs).to eq(2)
      expect(area.to_s).to eq("0.42 m^2")
    end

    it "treats bare numerics as exact constants" do
      expect((measurement * 2).to_s).to eq("2.40 m")
      expect((2 * measurement).to_s).to eq("2.40 m")
    end

    it "applies the significant figure rule to division" do
      speed = described_class.new("1.20 m") / described_class.new("0.4 s")
      expect(speed.sig_figs).to eq(1)
      expect(speed.to_s).to eq("3 m/s")
    end

    it "does not limit precision when an operand is exact" do
      product = described_class.exact("2.0 m") * described_class.new("1.20 m")
      expect(product.to_s).to eq("2.40 m^2")
    end
  end

  describe "temperature scale conversions" do
    it "preserves decimal places through the exact offset" do
      expect(described_class.new("1.20 tempC").convert_to("tempF").to_s).to eq("34.16 tempF")
    end

    it "handles the freezing point of water" do
      expect(described_class.new("0.0 tempC").convert_to("tempF").to_s).to eq("32.0 tempF")
    end

    it "converts to kelvin with the exact offset" do
      expect(described_class.new("1.20 tempC").convert_to("tempK").to_s).to eq("274.35 tempK")
    end

    it "converts from fahrenheit back to celsius" do
      expect(described_class.new("34.16 tempF").convert_to("tempC").to_s).to eq("1.20 tempC")
    end

    it "treats degree (differential) conversions as pure scaling" do
      expect(described_class.new("1.20 degC").convert_to("degF").to_s).to eq("2.16 degF")
    end
  end

  describe "chained calculations" do
    it "converts units first and computes afterwards without truncating intermediates" do
      length = described_class.new("1.15 m").convert_to("ft")
      expect((length * 2).to_s).to eq("7.55 ft")
      # truncating the intermediate to "3.77 ft" would give "7.54 ft"
    end

    it "keeps full precision across a convert-then-add chain" do
      total = described_class.new("1.20 m").convert_to("ft") + described_class.new("3.00 in").convert_to("ft")
      expect(total.scalar).to be_within(1e-12).of(4.187007874015748)
      expect(total.to_s).to eq("4.19 ft")
    end
  end

  describe "#inspect" do
    it "reports the significant figures" do
      expect(measurement.inspect).to eq("1.20 m (3 significant figures)")
    end

    it "reports exact values" do
      expect(described_class.exact("12 in").inspect).to eq("12 in (exact)")
    end
  end
end
