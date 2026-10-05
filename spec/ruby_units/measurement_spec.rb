# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyUnits::Measurement do
  subject(:measurement) { described_class.new("1.20 m") }

  describe ".new" do
    it "parses significant figures from the input string" do
      expect(described_class.new("1.20 m").sig_figs).to eq(3)
      expect(described_class.new("1.2 m").sig_figs).to eq(2)
      expect(described_class.new("0.0120 m").sig_figs).to eq(3)
      expect(described_class.new("1200 m").sig_figs).to eq(2)
      expect(described_class.new("1.20e3 m").sig_figs).to eq(3)
    end

    it "counts significant figures in numeric strings" do
      expect(described_class.count_sig_figs("1200.")).to eq(4)
      expect(described_class.count_sig_figs("0.0")).to eq(1)
      expect(described_class.count_sig_figs("-1.20e-3")).to eq(3)
    end

    it "does not treat 1.20 m and 1.2 m as the same precision" do
      expect(described_class.new("1.20 m")).not_to eq(described_class.new("1.2 m"))
    end

    it "accepts an explicit sig_figs override" do
      expect(described_class.new("1.23456 m", sig_figs: 4).sig_figs).to eq(4)
      expect(described_class.new(Unit.new("1.23456 m"), sig_figs: 4).sig_figs).to eq(4)
    end

    it "rejects invalid sig_figs" do
      expect { described_class.new("1.2 m", sig_figs: 0) }.to raise_error(ArgumentError)
      expect { described_class.new("1.2 m", sig_figs: 1.5) }.to raise_error(ArgumentError)
    end

    it "treats exact constants as having infinite precision" do
      expect(described_class.new("2.54 cm", exact: true)).to be_exact
      expect(described_class.exact("2.54 cm").sig_figs).to eq(Float::INFINITY)
    end

    it "treats rationals, complex numbers, and unit-only strings as exact" do
      expect(described_class.new("1/2 cup")).to be_exact
      expect(described_class.new("1+1i mm")).to be_exact
      expect(described_class.new("m")).to be_exact
    end

    it "treats bare Numeric and Unit input as exact unless sig_figs is given" do
      expect(described_class.new(5)).to be_exact
      expect(described_class.new(Unit.new("1.20 m"))).to be_exact
    end
  end

  describe "#to_s" do
    it "rounds only for display and preserves the input precision" do
      expect(described_class.new("1.20 m").to_s).to eq("1.20 m")
      expect(described_class.new("1.2 m").to_s).to eq("1.2 m")
      expect(described_class.new("1.23456 m", sig_figs: 3).to_s).to eq("1.23 m")
    end

    it "marks significant trailing zeros with a decimal point" do
      expect(described_class.new("1.20 m").to_s("cm")).to eq("120. cm")
      expect(described_class.new("1.20 m").to_s("mm")).to eq("1200. mm")
      expect(described_class.new("1.2e3 m").to_s).to eq("1200. m")
    end

    it "does not decorate integers without significant trailing zeros" do
      expect(described_class.new("5 m").to_s).to eq("5 m")
    end

    it "formats exact values like the underlying unit" do
      expect(described_class.exact("2.54 cm").to_s).to eq("2.54 cm")
    end
  end

  describe "internal value" do
    it "keeps the unrounded result until explicitly output or quantized" do
      sum = described_class.new("1.20 m") + described_class.new("3.45 cm")
      expect(sum.to_unit.scalar).to eq(1.2345)
      expect(sum.to_s).to eq("1.23 m")
    end

    it "quantizes the internal value only on demand" do
      quantized = described_class.new("1.2345 m", sig_figs: 3).quantize
      expect(quantized.to_unit.scalar).to eq(1.23)
      expect(quantized.to_s).to eq("1.23 m")
    end
  end

  describe "addition and subtraction" do
    it "keeps the least precise decimal place, compared in a common unit" do
      expect((described_class.new("1.20 m") + described_class.new("3.45 cm")).to_s).to eq("1.23 m")
      expect((described_class.new("1.20 m") - described_class.new("1.2 m")).to_s).to eq("0.0 m")
      expect((described_class.new("12.0 m") + described_class.new("0.05 m") + described_class.new("1.005 m")).to_s).to eq("13.1 m")
    end

    it "is not limited by significant figures of the operands" do
      # 1.20 m (3 sig figs) + 0.0345 m would be 1.23 m by decimal places,
      # even though 3.45 cm only has 3 significant figures
      sum = described_class.new("1.20 m") + described_class.new("3.45 cm")
      expect(sum.sig_figs).to eq(3)
    end

    it "propagates exact operands" do
      expect((described_class.new("1.20 m") + described_class.exact("3 cm")).to_s).to eq("1.23 m")
      expect(described_class.exact("1 m") + described_class.exact("2 m")).to be_exact
    end

    it "raises for incompatible units" do
      expect { described_class.new("1.20 m") + described_class.new("1.2 s") }.to raise_error(ArgumentError)
    end
  end

  describe "multiplication and division" do
    it "keeps the fewest significant figures of the operands" do
      expect((described_class.new("1.20 m") * described_class.new("1.2 m")).to_s).to eq("1.4 m^2")
      expect((described_class.new("10.0 m") / described_class.new("4.0 s")).to_s).to eq("2.5 m/s")
    end

    it "keeps the unrounded product internally" do
      product = described_class.new("1.25 m") * described_class.new("30.5 cm").convert_to("m")
      expect(product.to_unit.scalar).to be_within(1e-12).of(0.38125)
      expect(product.to_s).to eq("0.381 m^2")
    end

    it "treats numeric operands as exact" do
      expect((described_class.new("1.20 m") * 2).to_s).to eq("2.40 m")
      expect((described_class.new("1.20 m") / 4).to_s).to eq("0.300 m")
    end

    it "does not let exact constants limit precision" do
      inch = described_class.new("5.0 in")
      expect((inch * described_class.exact("2.54 cm/in")).to_s).to eq("13 cm")
    end
  end

  describe "powers" do
    it "preserves significant figures" do
      expect((described_class.new("2.5 m")**2).to_s).to eq("6.3 m^2")
    end
  end

  describe "unit conversion" do
    it "preserves significant figures through linear conversions" do
      expect(described_class.new("1.20 m").convert_to("cm").sig_figs).to eq(3)
      expect(described_class.new("1.20 m").to_s("ft")).to eq("3.94 ft")
      expect(described_class.new("1.20 m").to_s("km")).to eq("0.00120 km")
    end

    it "returns itself when no conversion is needed" do
      expect(measurement.convert_to("m")).to equal(measurement)
    end

    context "with temperature scales" do
      it "carries decimal-place precision through the offset" do
        expect(described_class.new("20.0 tempC").to_s("tempF")).to eq("68.0 tempF")
        expect(described_class.new("20.0 tempC").to_s("tempK")).to eq("293.2 tempK")
        expect(described_class.new("98.6 tempF").to_s("tempC")).to eq("37.00 tempC")
      end

      it "handles zero values on affine scales" do
        expect(described_class.new("0.0 tempC").to_s("tempF")).to eq("32.0 tempF")
      end

      it "keeps the unrounded converted value internally" do
        converted = described_class.new("20.0 tempC").convert_to("tempK")
        expect(converted.to_unit.scalar).to eq(293.15)
      end
    end
  end

  describe "comparisons" do
    it "compares values regardless of precision" do
      expect(described_class.new("1.20 m")).to be > described_class.new("1.1 m")
      expect(described_class.new("1.20 m")).to be < described_class.new("130 cm")
    end

    it "is equal only when value and precision match" do
      expect(described_class.new("1.20 m")).to eq(described_class.new("1.20 m"))
      expect(described_class.new("1.20 m")).not_to eq(described_class.new("1.2 m"))
      expect(described_class.new("1.20 m")).not_to eq("1.20 m")
    end

    it "supports hashing" do
      expect(described_class.new("1.20 m").hash).to eq(described_class.new("1.20 m").hash)
    end
  end

  describe "coercion of operands" do
    it "accepts strings, units, and measurements" do
      expect((described_class.new("1.20 m") + "3.45 cm").to_s).to eq("1.23 m")
      expect((described_class.new("1.20 m") + Unit.new("0.05 m")).to_s).to eq("1.25 m")
      expect((described_class.new("1.20 m") * Unit.new("2 m")).to_s).to eq("2.40 m^2")
    end

    it "rejects objects that cannot be coerced" do
      expect { described_class.new("1.20 m") + Object.new }.to raise_error(ArgumentError)
    end
  end

  describe "chained calculations" do
    it "does not truncate intermediate values" do
      # converting first and then multiplying keeps 0.38125 internally and
      # displays "0.381 m^2"; truncating the converted 30.5 cm to 0.31 m
      # before multiplying would display "0.39 m^2" instead
      area = described_class.new("1.25 m") * described_class.new("30.5 cm").convert_to("m")
      expect(area.to_s).to eq("0.381 m^2")

      truncated = described_class.new("1.25 m") * described_class.new("0.31 m")
      expect(truncated.to_s).to eq("0.39 m^2")
      expect(area.to_s).not_to eq(truncated.to_s)
    end
  end
end
