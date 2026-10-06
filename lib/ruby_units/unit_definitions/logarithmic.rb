# frozen_string_literal: true

# Logarithmic units. A distinction is made between:
#
# * reference-free ratios such as the decibel (dB)
# * absolute levels relative to a named reference such as dBm (1 milliwatt)
#   and dBW (1 watt)
#
# Level values are expressed as  log_scale * log_base(linear / reference).
# Ratios and levels are not linearly interchangeable: subtracting two levels
# yields a ratio, adding a ratio to a level yields a level, while adding two
# levels is invalid. Use RubyUnits::Unit#combine_power to add the underlying
# powers of two levels explicitly.

RubyUnits::Unit.define("decibel-milliwatt") do |unit|
  unit.scalar = 1
  unit.numerator = %w[<decibel-milliwatt>]
  unit.aliases = %w[dBm dBms decibel-milliwatt]
  unit.kind = :logarithmic_level
  unit.log_base = 10
  unit.log_scale = 10
  unit.log_reference = "<milliwatt>"
  unit.display_name = "dBm"
end

RubyUnits::Unit.define("decibel-watt") do |unit|
  unit.scalar = 1
  unit.numerator = %w[<decibel-watt>]
  unit.aliases = %w[dBW dBWs decibel-watt]
  unit.kind = :logarithmic_level
  unit.log_base = 10
  unit.log_scale = 10
  unit.log_reference = "<watt>"
  unit.display_name = "dBW"
end
