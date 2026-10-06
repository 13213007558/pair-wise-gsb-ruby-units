# frozen_string_literal: true

RSpec.describe "logarithmic units" do
  let(:db) { RubyUnits::Unit.new("3 dB") }
  let(:dbm) { RubyUnits::Unit.new("0 dBm") }

  describe "definitions" do
    specify { expect(db).to be_logarithmic }
    specify { expect(db).to be_log_ratio }
    specify { expect(db).not_to be_log_level }
    specify { expect(dbm).to be_log_level }
    specify { expect(dbm).not_to be_log_ratio }
    specify { expect(RubyUnits::Unit.new("0 dBW")).to be_log_level }

    specify "dB preserves the common power logarithm convention" do
      definition = RubyUnits::Unit.definition("dB")
      expect(definition.log_base).to eq(10)
      expect(definition.log_scale).to eq(10)
      expect(definition.log_reference).to be_nil
    end

    specify "absolute levels preserve their linear reference units" do
      expect(RubyUnits::Unit.definition("dBm").log_reference).to eq("mW")
      expect(RubyUnits::Unit.definition("dBW").log_reference).to eq("W")
    end
  end

  describe "conversion" do
    specify "round trips 0 dBm through mW" do
      linear = dbm.convert_to("mW")
      expect(linear).to eq(RubyUnits::Unit.new("1 mW"))
      expect(linear.convert_to("dBm")).to eq(dbm)
    end

    specify "converts a dB power ratio to and from a dimensionless ratio" do
      expect(RubyUnits::Unit.new("10 dB").convert_to("").scalar).to be_within(1e-12).of(10)
      expect(RubyUnits::Unit.new(10).convert_to("dB").scalar).to be_within(1e-12).of(10)
    end

    specify "converts between dBm and dBW using their references" do
      expect(RubyUnits::Unit.new("0 dBm").convert_to("dBW").scalar).to be_within(1e-9).of(-30)
      expect(RubyUnits::Unit.new("0 dBW").convert_to("dBm").scalar).to be_within(1e-9).of(30)
    end

    specify "does not convert an absolute level to an unreferenced ratio" do
      expect { dbm.convert_to("dB") }.to raise_error(ArgumentError, /absolute logarithmic level/)
    end

    specify "does not convert an unreferenced ratio to an absolute level" do
      expect { db.convert_to("dBm") }.to raise_error(ArgumentError, /logarithmic ratio/)
    end

    specify "does not convert dBm directly to a dimensionless number" do
      expect { dbm.convert_to("") }.to raise_error(ArgumentError, /Incompatible Units/)
    end

    specify "converts a dimensionless linear value nonlinearly to dB" do
      expect(RubyUnits::Unit.new(1).convert_to("dB").scalar).to eq(0)
    end
  end

  describe "arithmetic" do
    specify "subtracting two levels gives a ratio" do
      expect(RubyUnits::Unit.new("13 dBm") - RubyUnits::Unit.new("10 dBm")).to eq(RubyUnits::Unit.new("3 dB"))
    end

    specify "subtracting levels with different references still gives a ratio" do
      difference = RubyUnits::Unit.new("0 dBW") - RubyUnits::Unit.new("0 dBm")
      expect(difference.scalar).to be_within(1e-9).of(30)
    end

    specify "adding a ratio to a level gives a level" do
      expect(RubyUnits::Unit.new("0 dBm") + RubyUnits::Unit.new("3 dB")).to eq(RubyUnits::Unit.new("3 dBm"))
      expect(RubyUnits::Unit.new("3 dB") + RubyUnits::Unit.new("0 dBm")).to eq(RubyUnits::Unit.new("3 dBm"))
    end

    specify "subtracting a ratio from a level gives a level" do
      expect(RubyUnits::Unit.new("3 dBm") - RubyUnits::Unit.new("3 dB")).to eq(RubyUnits::Unit.new("0 dBm"))
    end

    specify "cannot add two absolute logarithmic levels numerically" do
      expect { dbm + RubyUnits::Unit.new("3 dBm") }.to raise_error(ArgumentError, /Cannot add two absolute logarithmic levels/)
    end

    specify "cannot multiply or divide logarithmic units like ordinary units" do
      expect { dbm * dbm }.to raise_error(ArgumentError, /Cannot multiply logarithmic units/)
      expect { dbm / dbm }.to raise_error(ArgumentError, /Cannot divide logarithmic units/)
      expect { dbm**2 }.to raise_error(ArgumentError, /Cannot raise logarithmic units/)
    end

    specify "explicitly combines equal signals by linear power" do
      combined = dbm.add_power(dbm)
      expect(combined.units).to eq("dBm")
      expect(combined).to be_within(RubyUnits::Unit.new("0.0001 dB")).of(RubyUnits::Unit.new("3.0103 dBm"))
      expect(combined.convert_to("mW")).to be_within(RubyUnits::Unit.new("1e-12 mW")).of(RubyUnits::Unit.new("2 mW"))
    end

    specify "combines levels with compatible but different reference units" do
      combined = RubyUnits::Unit.new("0 dBW").add_power(RubyUnits::Unit.new("1000 mW"))
      expect(combined).to be_within(RubyUnits::Unit.new("0.0001 dB")).of(RubyUnits::Unit.new("3.0103 dBW"))
    end

    specify "rejects incompatible linear quantities in explicit power addition" do
      expect { dbm.add_power(RubyUnits::Unit.new("1 V")) }.to raise_error(ArgumentError, /Incompatible power levels/)
    end
  end

  describe "domain rules" do
    specify "zero linear power maps to negative infinity and round trips" do
      level = RubyUnits::Unit.new("0 mW").convert_to("dBm")
      expect(level.scalar).to eq(-Float::INFINITY)
      expect(level.convert_to("mW")).to eq(RubyUnits::Unit.new("0 mW"))
    end

    specify "negative linear quantities are invalid" do
      expect { RubyUnits::Unit.new("-1 mW").convert_to("dBm") }.to raise_error(ArgumentError, /zero or positive/)
    end

    specify "infinite levels map to infinite and zero linear quantities" do
      expect(RubyUnits::Unit.new(Float::INFINITY, "dBm").convert_to("mW").scalar).to eq(Float::INFINITY)
      expect(Unit.new("0 mW").convert_to("dBm").convert_to("W")).to eq(RubyUnits::Unit.new("0 W"))
    end

    specify "large level differences are ratios and avoid requiring linear power" do
      difference = RubyUnits::Unit.new("1_000_000 dBm") - RubyUnits::Unit.new("-1_000_000 dBm")
      expect(difference).to eq(RubyUnits::Unit.new("2000000 dB"))
    end

    specify "0 dB is a ratio of one rather than an absolute zero" do
      expect(dbm).not_to be_zero
      expect(RubyUnits::Unit.new("0 dB")).not_to be_zero
      expect(RubyUnits::Unit.new("0 dB").convert_to("")).to eq(1)
    end
  end

  describe "separation from ordinary and temperature scales" do
    specify "ordinary multiplication and division remain dimensional" do
      expect(RubyUnits::Unit.new("2 m") * RubyUnits::Unit.new("3 m")).to eq(RubyUnits::Unit.new("6 m^2"))
      expect(RubyUnits::Unit.new("6 m") / RubyUnits::Unit.new("2 s")).to be_within(RubyUnits::Unit.new("1e-9 m/s")).of(RubyUnits::Unit.new("3 m/s"))
    end

    specify "temperatures retain offset and difference rules" do
      expect(RubyUnits::Unit.new("0 tempC")).not_to eq(RubyUnits::Unit.new("0 tempK"))
      expect { RubyUnits::Unit.new("1 tempC") + RubyUnits::Unit.new("1 tempC") }.to raise_error(ArgumentError, /Cannot add two temperatures/)
    end
  end
end
