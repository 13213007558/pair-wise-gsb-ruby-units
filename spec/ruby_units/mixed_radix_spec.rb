# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubyUnits::MixedRadix do
  describe "angles" do
    subject(:mixed_radix) { RubyUnits::Unit.mixed_radix(%w[° ′ ″], [60, 60]) }

    it "parses a configured sexagesimal angle and preserves an exact scalar" do
      angle = RubyUnits::Unit.new("12°59′59.999″", mixed_radix)

      expect(angle.units).to eq("deg")
      expect(angle.scalar).to eq(Rational(46_799_999, 3_600_000))
    end

    it "round trips an angle at thousandths of the final segment" do
      text = "12°59′59.999″"
      angle = RubyUnits::Unit.new(text, mixed_radix)

      expect(angle.to_s(mixed_radix, precision: Rational(1, 1000))).to eq(text)
      expect(RubyUnits::Unit.parse_mixed_radix(text, %w[° ′ ″], [60, 60])).to eq(angle)
    end

    it "carries rounding through every segment, including the first" do
      angle = RubyUnits::Unit.new(Rational(12, 1), "deg") + RubyUnits::Unit.new(Rational(59, 1), "arcmin") +
              RubyUnits::Unit.new(Rational(599_999, 10_000), "arcsec")

      expect(angle.to_s(mixed_radix, precision: Rational(1, 1000))).to eq("13°0′0.000″")
    end

    it "applies the sign to the complete negative angle and parses an unsigned final segment" do
      angle = RubyUnits::Unit.new("-0°0′1″", mixed_radix)

      expect(angle).to be_negative
      expect(angle).to eq(-RubyUnits::Unit.new(Rational(1, 3600), "deg"))
      expect(angle.to_s(mixed_radix)).to eq("-0°0′1″")
    end

    it "rejects a second sign in a later segment" do
      expect { RubyUnits::Unit.new("0°-0′1″", mixed_radix) }
        .to raise_error(ArgumentError, "\"0°-0′1″\" is not a valid mixed-radix representation")
    end

    it "rounds a small negative value without making a positive unsigned segment representation" do
      angle = RubyUnits::Unit.new(-Rational(1, 1000), "deg")

      expect(angle.to_s(mixed_radix)).to eq("-0°0′4″")
    end

    it "does not attach a negative sign to an exact zero" do
      expect(RubyUnits::Unit.new(0, "deg").to_s(mixed_radix)).to eq("0°0′0″")
    end
  end

  describe "durations" do
    subject(:mixed_radix) { RubyUnits::Unit.mixed_radix(%w[h min s], [60, 60]) }

    it "parses a duration and preserves an exact scalar" do
      duration = RubyUnits::Unit.new("1 h 2 min 3.5 s", mixed_radix)

      expect(duration.units).to eq("h")
      expect(duration.scalar).to eq(Rational(7447, 7200))
    end

    it "round trips a duration at tenths of the final segment" do
      text = "1 h 2 min 3.5 s"
      duration = RubyUnits::Unit.new(text, mixed_radix)

      expect(duration.to_s(mixed_radix, precision: Rational(1, 10))).to eq(text)
      expect(RubyUnits::Unit.parse_mixed_radix(text, %w[h min s], [60, 60])).to eq(duration)
    end

    it "rounds negative durations by whole-value semantics" do
      duration = RubyUnits::Unit.new("-1 h 2 min 3.4 s", mixed_radix)

      expect(duration.to_s(mixed_radix)).to eq("-1 h 2 min 3 s")
    end

    it "carries a final-segment overflow into earlier segments" do
      duration = RubyUnits::Unit.new(Rational(7214, 7200), "h")

      expect(duration.to_s(mixed_radix)).to eq("1 h 0 min 7 s")
    end
  end

  describe "validation" do
    it "requires a complete mixed-radix string in the two-argument form" do
      mixed_radix = RubyUnits::Unit.mixed_radix(%w[h min s], [60, 60])

      expect { RubyUnits::Unit.new(2, mixed_radix) }
        .to raise_error(ArgumentError, "Invalid Unit Format")
    end

    it "rejects segment units with incompatible dimensions" do
      expect { RubyUnits::Unit.mixed_radix(%w[deg m], [60]) }
        .to raise_error(ArgumentError, /Incompatible Units/)
    end

    it "rejects a radix count that does not match the segment count" do
      expect { RubyUnits::Unit.mixed_radix(%w[h min s], [60]) }
        .to raise_error(ArgumentError, "Expected 2 radices for 3 units")
    end

    it "rejects radices that are not integers greater than one" do
      expect { RubyUnits::Unit.mixed_radix(%w[h min s], [60, 1]) }
        .to raise_error(ArgumentError, "Radices must be integers greater than 1")
    end

    it "rejects a value outside the range for a non-first segment" do
      mixed_radix = RubyUnits::Unit.mixed_radix(%w[h min s], [60, 60])

      expect { RubyUnits::Unit.new("1 h 60 min 0 s", mixed_radix) }
        .to raise_error(ArgumentError, "Segment value must be less than 60")
    end

    it "rejects a final-segment precision that does not produce integer increments" do
      mixed_radix = RubyUnits::Unit.mixed_radix(%w[h min s], [60, 60])

      expect { mixed_radix.format(RubyUnits::Unit.new(1, "h"), Rational(2, 3)) }
        .to raise_error(ArgumentError, "Precision must be an integer or the reciprocal of an integer")
    end
  end
end
