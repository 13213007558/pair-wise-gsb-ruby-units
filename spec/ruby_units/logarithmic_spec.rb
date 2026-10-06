# frozen_string_literal: true

RSpec.describe "logarithmic units" do
  describe "definitions" do
    it "defines the decibel as a reference-free ratio" do
      definition = Unit.definition("<decibel>")
      expect(definition.log_base).to eq(10)
      expect(definition.log_scale).to eq(10)
      expect(definition.log_reference).to be_nil
      expect(Unit.new("3 dB")).to be_logarithmic
      expect(Unit.new("3 dB")).not_to be_logarithmic_level
    end

    it "defines dBm relative to one milliwatt" do
      definition = Unit.definition(Unit.unit_map["dBm"])
      expect(definition.log_base).to eq(10)
      expect(definition.log_scale).to eq(10)
      expect(definition.log_reference).to eq("<milliwatt>")
      expect(Unit.new("3 dBm")).to be_logarithmic_level
    end

    it "defines dBW relative to one watt" do
      definition = Unit.definition(Unit.unit_map["dBW"])
      expect(definition.log_reference).to eq("<watt>")
      expect(Unit.new("3 dBW")).to be_logarithmic_level
    end

    it "preserves base and scale through conversions" do
      level = Unit.new("13 dBm")
      expect(level.log_definition.log_base).to eq(10)
      expect(level.log_definition.log_scale).to eq(10)
      expect(level.convert_to("dBW").log_definition.log_base).to eq(10)
    end
  end

  describe "round trip between dBm and mW" do
    it "converts 0 dBm to exactly 1 mW and back" do
      zero_dbm = Unit.new("0 dBm")
      expect(zero_dbm.convert_to("mW")).to eq(Unit.new("1 mW"))
      expect(Unit.new("1 mW").convert_to("dBm").scalar).to be_within(1e-12).of(0)
    end

    it "converts 30 dBm to 1000 mW" do
      expect(Unit.new("30 dBm").convert_to("mW").scalar).to be_within(1e-9).of(1000)
      expect(Unit.new("1000 mW").convert_to("dBm").scalar).to be_within(1e-9).of(30)
    end

    it "converts 10 dBm to 10 mW" do
      expect(Unit.new("10 dBm")).to eq(Unit.new("10 mW").convert_to("dBm"))
    end
  end

  describe "absolute level arithmetic" do
    specify "subtracting two levels yields a ratio" do
      ratio = Unit.new("13 dBm") - Unit.new("10 dBm")
      expect(ratio).to be_logarithmic
      expect(ratio).not_to be_logarithmic_level
      expect(ratio.units).to eq("dB")
      expect(ratio.scalar).to be_within(1e-9).of(3)
    end

    specify "subtracting levels with different references accounts for the reference offset" do
      ratio = Unit.new("30 dBm") - Unit.new("0 dBW")
      expect(ratio.units).to eq("dB")
      expect(ratio.scalar.abs).to be < 1e-9
    end

    specify "adding a ratio to a level yields a level" do
      expect(Unit.new("0 dBm") + Unit.new("3 dB")).to eq(Unit.new("3 dBm"))
      expect(Unit.new("3 dB") + Unit.new("0 dBm")).to eq(Unit.new("3 dBm"))
      expect(Unit.new("3 dBm") - Unit.new("3 dB")).to eq(Unit.new("0 dBm"))
    end

    specify "adding two levels directly is not allowed" do
      expect { Unit.new("1 dBm") + Unit.new("2 dBm") }
        .to raise_error(ArgumentError, /combine_power/)
    end

    specify "a ratio cannot be converted into an absolute level by multiplication or addition" do
      expect { Unit.new("3 dB") + Unit.new("1 dBm") }.not_to raise_error
      expect { Unit.new("3 dBm") + Unit.new("1 dBm") }.to raise_error(ArgumentError)
      expect { Unit.new("3 dB") - Unit.new("1 dBm") }.to raise_error(ArgumentError)
    end
  end

  describe "combine_power" do
    it "combines two equal signals and returns a 3.0103 dB increase" do
      combined = Unit.new("0 dBm").combine_power(Unit.new("0 dBm"))
      expect(combined.units).to eq("dBm")
      expect(combined.scalar).to be_within(1e-3).of(3.0103)
      expect(combined.convert_to("mW").scalar).to be_within(1e-9).of(2)
    end

    it "combines unequal coherent powers in the linear domain" do
      combined = Unit.new("13 dBm").combine_power(Unit.new("10 dBm"))
      expect(combined.convert_to("mW").scalar).to be_within(1e-6).of(29.9526231496888)
    end

    it "accepts a linear power argument" do
      combined = Unit.new("0 dBm").combine_power(Unit.new("1 W"))
      expect(combined).to eq(Unit.new("1001 mW").convert_to("dBm"))
    end

    it "is not available for ratios" do
      expect { Unit.new("3 dB").combine_power(Unit.new("3 dB")) }
        .to raise_error(ArgumentError, /absolute logarithmic levels/)
    end

    it "rejects incompatible dimensional quantities" do
      expect { Unit.new("0 dBm").combine_power(Unit.new("1 m")) }
        .to raise_error(ArgumentError)
    end
  end

  describe "reference conversions" do
    it "converts between dBm and dBW using the 30 dB reference separation" do
      expect(Unit.new("0 dBW").convert_to("dBm").scalar).to be_within(1e-12).of(30)
      expect(Unit.new("30 dBm").convert_to("dBW").scalar).to be_within(1e-9).of(0)
      expect(Unit.new("10 dBm")).to eq(Unit.new("0 dBW").convert_to("dBm") - Unit.new("20 dB"))
    end

    it "converts linear watt and milliwatt quantities to levels" do
      expect(Unit.new("1 W").convert_to("dBm")).to eq(Unit.new("30 dBm"))
      expect(Unit.new("1 W").convert_to("dBW").scalar).to be_within(1e-12).of(0)
    end
  end

  describe "ratio arithmetic" do
    it "adds and subtracts ratios as gain on the log scale" do
      expect(Unit.new("3 dB") + Unit.new("7 dB")).to eq(Unit.new("10 dB"))
      expect(Unit.new("10 dB") - Unit.new("3 dB")).to eq(Unit.new("7 dB"))
    end

    it "allows linear scaling of a ratio by a unitless number" do
      expect(Unit.new("6 dB") * 2).to eq(Unit.new("12 dB"))
      expect(Unit.new("6 dB") / 2).to eq(Unit.new("3 dB"))
      expect(2 * Unit.new("6 dB")).to eq(Unit.new("12 dB"))
    end

    it "does not multiply or divide two logarithmic quantities" do
      expect { Unit.new("3 dB") * Unit.new("2 dB") }.to raise_error(ArgumentError)
      expect { Unit.new("3 dB") / Unit.new("2 dB") }.to raise_error(ArgumentError)
    end

    it "does not scale an absolute level by a number" do
      expect { Unit.new("3 dBm") * 2 }.to raise_error(ArgumentError)
      expect { Unit.new("3 dBm") / 2 }.to raise_error(ArgumentError)
    end

    it "does not raise logarithmic units to powers or roots" do
      expect { Unit.new("3 dB") ** 2 }.to raise_error(ArgumentError)
      expect { Unit.new("3 dBm")**2 }.to raise_error(ArgumentError)
    end

    it "can be converted to and from a unitless ratio" do
      expect(Unit.new("10 dB").convert_to("").scalar).to be_within(1e-9).of(10)
      expect(Unit.new(10).convert_to("dB").scalar).to be_within(1e-9).of(10)
    end

    it "cannot convert a ratio to a power unit or a level to a dimensional unit directly" do
      expect { Unit.new("3 dB").convert_to("mW") }.to raise_error(ArgumentError)
      expect { Unit.new(10).convert_to("dBm") }.to raise_error(ArgumentError)
    end
  end

  describe "domain rules" do
    it "maps zero linear power to negative infinity" do
      level = Unit.new("0 mW").convert_to("dBm")
      expect(level.scalar).to eq(-Float::INFINITY)
      expect(level.convert_to("mW").scalar).to eq(0)
    end

    it "rejects negative linear power" do
      expect { Unit.new("-1 mW").convert_to("dBm") }
        .to raise_error(ArgumentError, /non-positive/)
    end

    it "supports infinite levels" do
      expect(Unit.new(Float::INFINITY, "dBm").convert_to("mW").scalar).to eq(Float::INFINITY)
      expect(Unit.new(Float::INFINITY, "dBm")).to eq(Unit.new(Float::INFINITY, "dBW"))
    end

    it "combines powers consistently for infinite values" do
      expect(Unit.new(Float::INFINITY, "dBm").combine_power(Unit.new("0 dBm")).scalar).to eq(Float::INFINITY)
      expect(Unit.new(-Float::INFINITY, "dBm").combine_power(Unit.new("0 dBm"))).to eq(Unit.new("0 dBm"))
      expect(Unit.new(Float::INFINITY, "dBm").combine_power(Unit.new(-Float::INFINITY, "dBm")).scalar)
        .to eq(Float::INFINITY)
    end

    it "rejects subtracting infinities with no defined difference" do
      expect { Unit.new(Float::INFINITY, "dBm") - Unit.new(Float::INFINITY, "dBm") }
        .to raise_error(ArgumentError)
    end

    it "handles very large level differences without overflowing" do
      ratio = Unit.new("300 dBm") - Unit.new("-300 dBm")
      expect(ratio.scalar).to be_within(1e-9).of(600)
      expect(Unit.new("1000 dBm").convert_to("mW").scalar).to be_within(1e85).of(1e100)
      expect(Unit.new("10_000 dBm").convert_to("mW").scalar).to eq(Float::INFINITY)
    end

    it "rejects complex and not-a-number scalars" do
      expect { Unit.new(Complex(1, 2), "dB") }.to raise_error(ArgumentError)
      expect { Unit.new(Float::NAN, "dBm") }.to raise_error(ArgumentError)
    end

    it "keeps ordering consistent on the log scale" do
      expect(Unit.new("10 dBm")).to eq(Unit.new("-20 dBW"))
      expect(Unit.new("11 dBm")).to be > Unit.new("-20 dBW")
      expect(Unit.new("0 dBm")) .not_to eq(0)
      expect(Unit.new("0 dB")).to eq(0)
    end

    it "does not treat a level as zero" do
      expect(Unit.new("0 dBm")).not_to be_zero
      expect(Unit.new("0 dB")).to be_zero
    end
  end

  describe "separation from ordinary and temperature units" do
    it "keeps ordinary dimensional multiplication unchanged" do
      expect(Unit.new("2 m") * Unit.new("3 m")).to eq(Unit.new("6 m^2"))
      expect { Unit.new("1 m") * Unit.new("1 dB") }.to raise_error(ArgumentError)
      expect { Unit.new("1 dB") * Unit.new("1 m") }.to raise_error(ArgumentError)
    end

    it "does not let temperatures participate in logarithmic rules" do
      expect(Unit.new("100 tempK") - Unit.new("90 tempK")).to eq(Unit.new("10 degK"))
      expect(Unit.new("100 tempK")).to be_temperature
      expect(Unit.new("10 dBm")).not_to be_temperature
      expect { Unit.new("10 dBm") + Unit.new("10 tempK") }.to raise_error(ArgumentError)
    end

    it "refuses temperature multiplication as before" do
      expect { Unit.new("1 tempK") * Unit.new("1 tempK") }.to raise_error(ArgumentError)
    end
  end
end
