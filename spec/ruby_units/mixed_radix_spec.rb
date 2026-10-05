# frozen_string_literal: true

require "spec_helper"

describe RubyUnits::MixedRadix do
  before(:all) do
    RubyUnits::Unit.define("arcmin") do |unit|
      unit.definition = RubyUnits::Unit.new(Rational(1, 60), "deg")
      unit.aliases = %w[arcmin]
    end
    RubyUnits::Unit.define("arcsec") do |unit|
      unit.definition = RubyUnits::Unit.new(Rational(1, 60), "arcmin")
      unit.aliases = %w[arcsec]
    end
  end

  after(:all) do
    RubyUnits::Unit.undefine!("arcmin")
    RubyUnits::Unit.undefine!("arcsec")
  end

  subject(:dms) do
    described_class.new(units: %w[deg arcmin arcsec], bases: [60, 60], separators: ["°", "′", "″"])
  end

  let(:hms) { described_class.new(units: %w[hour min sec], bases: [60, 60], separators: [":", ":", ""]) }

  describe "#initialize" do
    it "accepts a valid segment definition" do
      expect(dms.units).to eq %w[deg arcmin arcsec]
      expect(dms.bases).to eq [60, 60]
      expect(dms.separators).to eq ["°", "′", "″"]
    end

    it "requires at least two segments" do
      expect { described_class.new(units: %w[deg], bases: []) }.to raise_error(ArgumentError)
    end

    it "requires one fewer base than units" do
      expect { described_class.new(units: %w[deg arcmin], bases: [60, 60]) }.to raise_error(ArgumentError)
    end

    it "requires integer bases greater than 1" do
      expect { described_class.new(units: %w[deg arcmin], bases: [1]) }.to raise_error(ArgumentError)
      expect { described_class.new(units: %w[deg arcmin], bases: [59.5]) }.to raise_error(ArgumentError)
    end

    it "rejects segment units with incompatible dimensions" do
      expect { described_class.new(units: %w[deg kg], bases: [60]) }.to raise_error(ArgumentError, /not compatible/)
      expect { described_class.new(units: %w[hour min m], bases: [60, 60]) }.to raise_error(ArgumentError, /not compatible/)
    end

    it "rejects unknown segment units" do
      expect { described_class.new(units: %w[deg doohickey], bases: [60]) }.to raise_error(ArgumentError)
    end

    it "rejects a carry base that does not match the unit ratio" do
      expect { described_class.new(units: %w[deg arcmin], bases: [100]) }.to raise_error(ArgumentError, /carry base/)
    end

    it "requires one separator per segment and only the last may be empty" do
      expect { described_class.new(units: %w[deg arcmin], bases: [60], separators: ["°"]) }
        .to raise_error(ArgumentError, /separators/)
      expect { described_class.new(units: %w[deg arcmin], bases: [60], separators: ["", "′"]) }
        .to raise_error(ArgumentError, /only the last/)
    end
  end

  describe "#parse" do
    it "parses an angle into a single Unit in the first segment unit" do
      angle = dms.parse("12°59′59.999″")
      expect(angle).to be_a(RubyUnits::Unit)
      expect(angle.units).to eq "deg"
      expect(angle.scalar).to eq Rational(12) + Rational(59, 60) + Rational(59_999, 3_600_000)
    end

    it "parses a duration into a single Unit" do
      expect(hms.parse("12:34:56.789").scalar).to eq Rational(12) + Rational(34, 60) + Rational(56_789, 3_600_000)
    end

    it "keeps integral values as Integers" do
      scalar = dms.parse("13°0′0″").scalar
      expect(scalar).to eq 13
      expect(scalar).to be_a Integer
    end

    it "allows trailing segments to be omitted" do
      expect(dms.parse("12°30′").scalar).to eq Rational(25, 2)
      expect(dms.parse("12°").scalar).to eq 12
    end

    it "applies a leading sign to the whole value" do
      expect(dms.parse("-12°30′").scalar).to eq Rational(-25, 2)
      expect(dms.parse("+3°15′").scalar).to eq Rational(13, 4)
    end

    it "reads a negative value with a zero first segment as negative" do
      angle = dms.parse("-0°1′")
      expect(angle.scalar).to eq Rational(-1, 60)
      expect(angle.scalar).to be_negative
    end

    it "rejects strings that do not match the segments" do
      expect { dms.parse("not an angle") }.to raise_error(ArgumentError)
      expect { dms.parse("12°59′59.999") }.to raise_error(ArgumentError)
      expect { hms.parse("12°34′56″") }.to raise_error(ArgumentError)
    end

    it "rejects signs on individual segments" do
      expect { dms.parse("12°-3′") }.to raise_error(ArgumentError)
    end
  end

  describe "#format" do
    it "formats a Unit with the requested last-segment precision" do
      expect(dms.format(dms.parse("12°59′59.999″"), precision: 3)).to eq "12°59′59.999″"
      expect(hms.format(hms.parse("12:34:56.789"), precision: 3)).to eq "12:34:56.789"
    end

    it "carries rounding all the way up to the first segment" do
      expect(dms.format(dms.parse("12°59′59.999″"), precision: 2)).to eq "13°0′0.00″"
      expect(hms.format(hms.parse("23:59:59.9995"), precision: 3)).to eq "24:0:0.000"
    end

    it "normalizes overflowing segments" do
      expect(dms.format(dms.parse("179°59′60.00″"), precision: 2)).to eq "180°0′0.00″"
    end

    it "formats negative values with a single leading sign" do
      formatted = dms.format(RubyUnits::Unit.new("-1 arcmin"), precision: 0)
      expect(formatted).to eq "-0°1′0″"
      expect(dms.parse(formatted).scalar).to eq Rational(-1, 60)
    end

    it "does not emit a sign when a negative value rounds to zero" do
      expect(dms.format(Rational(-1, 10**9), precision: 2)).to eq "0°0′0.00″"
    end

    it "keeps Rational scalars exact" do
      expect(hms.format(RubyUnits::Unit.new(Rational(1, 3), "hour"))).to eq "0:20:0"
      expect(hms.format(RubyUnits::Unit.new(Rational(1, 7), "hour"))).to eq "0:8:240/7"
      expect(dms.format(RubyUnits::Unit.new(Rational(1, 7), "deg"), precision: 4)).to eq "0°8′34.2857″"
    end

    it "interprets bare numerics in the first segment unit" do
      expect(dms.format(13, precision: 0)).to eq "13°0′0″"
    end

    it "converts compatible units before formatting" do
      expect(hms.format(RubyUnits::Unit.new("90 min"), precision: 0)).to eq "1:30:0"
    end

    it "rejects values with incompatible dimensions" do
      expect { dms.format(RubyUnits::Unit.new("5 kg")) }.to raise_error(ArgumentError, /not compatible/)
    end

    it "rejects invalid precisions" do
      expect { dms.format(1, precision: -1) }.to raise_error(ArgumentError)
      expect { dms.format(1, precision: 1.5) }.to raise_error(ArgumentError)
    end
  end

  describe "round trips" do
    it "round-trips angles" do
      ["0°0′0″", "12°59′59.999″", "-45°30′15.25″", "360°0′0.0″"].each do |string|
        precision = string[/\.(\d+)/, 1]&.length || 0
        expect(dms.format(dms.parse(string), precision: precision)).to eq string
      end
    end

    it "round-trips durations" do
      ["0:0:0", "12:34:56.789", "99:59:59.5", "-1:15:30"].each do |string|
        precision = string[/\.(\d+)/, 1]&.length || 0
        expect(hms.format(hms.parse(string), precision: precision)).to eq string
      end
    end
  end
end
