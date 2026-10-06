# frozen_string_literal: true

module RubyUnits
  class Ucum
    # UCUM decimal (metric) prefixes with their strictly case-sensitive codes.
    # @see http://unitsofmeasure.org/ucum.html#para-31
    DECIMAL_PREFIXES = {
      "Y"  => 1e24,
      "Z"  => 1e21,
      "E"  => 1e18,
      "P"  => 1e15,
      "T"  => 1e12,
      "G"  => 1e9,
      "M"  => 1e6,
      "k"  => 1e3,
      "h"  => 1e2,
      "da" => 1e1,
      "d"  => Rational(1, 10),
      "c"  => Rational(1, 100),
      "m" => Rational(1, 1000),
      "u"  => Rational(1, 1000_000),
      "n"  => Rational(1, 1000_000_000),
      "p"  => Rational(1, 1000_000_000_000),
      "f"  => Rational(1, 1000_000_000_000_000),
      "a"  => Rational(1, 1000_000_000_000_000_000),
      "z"  => Rational(1, 1000_000_000_000_000_000_000),
      "y"  => Rational(1, 1000_000_000_000_000_000_000_000)
    }.freeze

    # Atom kinds.
    PROPORTIONAL = :proportional
    SPECIAL = :special
    AFFINE = :affine

    # UCUM atoms supported by this entry point.
    #
    # +value+ is the string parsed by the (lenient) RubyUnits::Unit parser to
    # obtain the proportional conversion factor. +prefixable+ marks the atoms
    # which accept {DECIMAL_PREFIXES}. Affine atoms (point temperatures)
    # instead carry +point+ and +degree+ RubyUnits unit names. Special atoms
    # are recognized only to raise a precise error identifying the function
    # and the position of the unsupported code.
    #
    # @see http://unitsofmeasure.org/ucum.html#section-Semantics
    ATOMS = {
      # Base and other simple (unbracketed) units
      "m"   => { value: "m",   prefixable: true },
      "g"   => { value: "g",   prefixable: true },
      "s"   => { value: "s",   prefixable: true },
      "mol" => { value: "mol", prefixable: true },
      "cd"  => { value: "cd",  prefixable: true },
      "rad" => { value: "rad", prefixable: true },
      "sr"  => { value: "sr",  prefixable: true },
      "Hz"  => { value: "Hz",  prefixable: true },
      "N"   => { value: "N",   prefixable: true },
      "Pa"  => { value: "Pa",  prefixable: true },
      "J"   => { value: "J",   prefixable: true },
      "W"   => { value: "W",   prefixable: true },
      "V"   => { value: "V",   prefixable: true },
      "F"   => { value: "F",   prefixable: true },
      "S"   => { value: "S",   prefixable: true },
      "H"   => { value: "H",   prefixable: true },
      "Wb"  => { value: "Wb",  prefixable: true },
      "T"   => { value: "T",   prefixable: true },
      "Bq"  => { value: "Bq",  prefixable: true },
      "Gy"  => { value: "Gy",  prefixable: true },
      "Sv"  => { value: "Sv",  prefixable: true },
      "lm"  => { value: "lm",  prefixable: true },
      "lx"  => { value: "lux", prefixable: true },
      "A"   => { value: "A" },
      "K"   => { value: "kelvin", prefixable: true },
      "L"   => { value: "L", prefixable: true },
      "l"   => { value: "l", prefixable: true },
      "Ohm" => { value: "Ohm", prefixable: true },
      "u"   => { value: "u" },
      "Da"  => { value: "Da", prefixable: true },
      "%"   => { value: "%" },

      # Common bracketed units
      "[degC]"  => { value: "degC" },
      "[degR]"  => { value: "degR" },
      "[in_i]"  => { value: "in" },
      "[ft_i]"  => { value: "ft" },
      "[yd_i]"  => { value: "yd" },
      "[mi_i]"  => { value: "mi" },
      "[oz_av]" => { value: "oz" },
      "[lb_av]" => { value: "lb" },
      "[stone]" => { value: "stone" },
      "[carat]" => { value: "ct" },
      "[lbf]"   => { value: "lbf" },
      "[psi]"   => { value: "psi" },
      "[bar]"   => { value: "bar" },
      "[atm]"   => { value: "atm" },
      "[Torr]"  => { value: "Torr" },
      "[cal_th]" => { value: "cal" },
      "[Cal]"    => { value: "Cal" },
      "[Btu_IT]" => { value: "Btu" },
      "[hp]"     => { value: "hp" },
      "min" => { value: "min" },
      "h"   => { value: "h" },
      "d"   => { value: "d" },
      "wk"  => { value: "wk" },
      "[deg]" => { value: "deg" },
      "[pi]"  => { value: ::Math::PI },

      # Point temperatures are affine units (factor + offset). The bracketed
      # Fahrenheit code denotes both the proportional degree unit and, when
      # standing alone, the point-temperature unit.
      "Cel" => { kind: AFFINE, point: "tempC", degree: "degC" },
      "[degF]" => { value: "degF", kind: AFFINE, point: "tempF", degree: "degF" },

      # UCUM special units. These are recognized so a precise error giving
      # the function and the position of the unsupported code is raised
      # instead of a generic parse failure.
      "[pH]"  => { kind: SPECIAL, function: "log10" },
      "[Np]"  => { kind: SPECIAL, function: "ln" },
      "[B]"   => { kind: SPECIAL, function: "log10" },
      "[B10]" => { kind: SPECIAL, function: "log10" },
      "[B12]" => { kind: SPECIAL, function: "2*log12" },
      "[Bln]" => { kind: SPECIAL, function: "ln" },
      "[bd]"  => { kind: SPECIAL, function: "2*log10" }
    }.freeze

    # Reverse lookup from the RubyUnits canonical unit name to a UCUM code.
    # RubyUnits canonical names are the definition names without brackets.
    RUBY_TO_UCUM = {
      "kelvin" => "K",
      "lux" => "lx",
      "inch" => "[in_i]",
      "foot" => "[ft_i]",
      "yard" => "[yd_i]",
      "mile" => "[mi_i]",
      "ounce" => "[oz_av]",
      "pound" => "[lb_av]",
      "pound-force" => "[lbf]",
      "torr" => "[Torr]",
      "calorie" => "[cal_th]",
      "Calorie" => "[Cal]",
      "btu" => "[Btu_IT]",
      "horsepower" => "[hp]",
      "minute" => "min",
      "hour" => "h",
      "day" => "d",
      "week" => "wk",
      "degree" => "[deg]",
      "tempC" => "Cel",
      "tempF" => "[degF]",
      "celsius" => "[degC]",
      "fahrenheit" => "[degF]",
      "rankine" => "[degR]",
      "carat" => "[carat]"
    }.freeze
  end
end
