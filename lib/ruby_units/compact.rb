# frozen_string_literal: true

class RubyUnits::Unit
  # The outcome of a {Unit#compact} search.
  #
  # When the candidate units can fully express the original unit, {#covered?}
  # is true and {#unit} holds the compacted unit with the conversion scale
  # folded into its scalar. Otherwise {#unit} is the original unit (its
  # representation is preserved) and {#uncovered_dimensions} lists the
  # dimensions that none of the candidates can express.
  class CompactResult
    # @return [RubyUnits::Unit] the compacted unit, or the original unit when
    #   no complete representation was found
    attr_reader :unit

    # @return [Numeric, nil] total display cost of the chosen representation,
    #   or nil when the search failed
    attr_reader :cost

    # @return [Hash{String => Integer}] candidate unit names mapped to the
    #   exponent used for them in the chosen representation (negative exponents
    #   denote the denominator). Empty when the search failed.
    attr_reader :terms

    # @return [Array<Symbol>] dimensions of the original unit (e.g. :length,
    #   :angle) that none of the candidate units contain. Note that this only
    #   reports dimensions that are structurally absent from the candidates;
    #   when it is empty but {#covered?} is false, the remaining gap is caused
    #   by the bounded exponent range or by linear dependencies between the
    #   candidates.
    attr_reader :uncovered_dimensions

    def initialize(unit:, cost:, terms:, uncovered_dimensions:)
      @unit = unit
      @cost = cost
      @terms = terms.freeze
      @uncovered_dimensions = uncovered_dimensions.freeze
    end

    # true when the candidates fully cover the dimensions of the original unit
    # @return [Boolean]
    def covered?
      !@cost.nil?
    end

    # @return [String]
    def inspect
      return "#<#{self.class.name}: #{unit} (cost #{cost})>" if covered?

      "#<#{self.class.name}: #{unit} (uncovered: #{uncovered_dimensions.join(', ')})>"
    end
  end

  # Search for the cheapest way to display this unit using a caller-supplied
  # table of candidate units and their display costs.
  #
  # Calculation results are often displayed in base units (e.g. "kg*m/s^2")
  # even though a derived unit (e.g. "N") would be more compact. This method
  # picks the combination of candidate units that
  #
  # 1. spans exactly the same dimensions as the original unit, and
  # 2. minimizes the total display cost (the cost of each candidate multiplied
  #    by the absolute exponent it is used with),
  #
  # and folds the resulting scale exactly into the scalar of the returned
  # unit, so converting the result back to the original units yields exactly
  # the same quantity.
  #
  # Candidates may appear in the numerator and the denominator. The search is
  # bounded: each candidate is tried with integer exponents from
  # +max_exponent+ to +-max_exponent+, so equivalent combinations cannot be
  # retried indefinitely. Derived units in the candidate table may be linearly
  # dependent (e.g. "J" and "N*m"); when several representations are equally
  # cheap the choice is stable: fewer unit symbols win, and remaining ties are
  # resolved in favor of candidates listed earlier.
  #
  # Dimensionless units that carry a semantic marker (e.g. "rad") are treated
  # as their own dimension and are never silently dropped: they can only be
  # covered by candidates that share that dimension.
  #
  # @example
  #   RubyUnits::Unit.new("5.6 kg*m/s^2").compact(%w[N J Pa kg m s]).unit
  #   # => 5.6 N
  #   RubyUnits::Unit.new("5.6 kg*m/s^2").compact("N" => 1, "kg" => 2, "m" => 2, "s" => 2).unit
  #   # => 5.6 N
  #
  # @param candidates [Array<String, RubyUnits::Unit>, Hash{String, RubyUnits::Unit => Numeric}, nil]
  #   the units available for the compact representation. A Hash maps each
  #   candidate to its display cost; an Array assigns every candidate a cost
  #   of 1. May also be passed as keyword-style pairs (e.g. +compact("N" => 1)+).
  # @param max_exponent [Integer] largest absolute exponent (>= 1) tried for
  #   each candidate, in both the numerator and the denominator
  # @param costs [Hash{String => Numeric}] candidate units and their display
  #   costs, collected from keyword-style arguments when +candidates+ is omitted
  # @return [RubyUnits::Unit::CompactResult]
  # @raise [ArgumentError] when the unit or one of the candidates is a
  #   temperature scale, when a display cost is negative, or when
  #   +max_exponent+ is not a positive Integer
  def compact(candidates = nil, max_exponent: 2, **costs)
    raise ArgumentError, "max_exponent must be a positive Integer" unless max_exponent.is_a?(Integer) && max_exponent.positive?
    raise ArgumentError, "Cannot compact temperatures" if temperature?
    raise ArgumentError, "pass candidates either as a single argument or as keyword pairs, not both" if candidates && !costs.empty?

    candidates = costs if candidates.nil?
    raise ArgumentError, "no candidate units given" if candidates.nil?

    entries = compact_candidate_entries(candidates)
    target = unit_signature_vector
    return CompactResult.new(unit: self, cost: 0, terms: {}, uncovered_dimensions: []) if target.all?(&:zero?)

    active = entries.reject { |entry| entry[:vector].all?(&:zero?) }
    exponents = compact_search(target, active, max_exponent)
    unless exponents
      return CompactResult.new(unit: self, cost: nil, terms: {}, uncovered_dimensions: compact_uncovered_dimensions(target, active))
    end

    terms = {}
    cost = 0
    active.each_with_index do |entry, index|
      exponent = exponents[index]
      next if exponent.zero?

      terms[entry[:name]] = exponent
      cost += entry[:cost] * exponent.abs
    end
    CompactResult.new(unit: compact_build_unit(active, exponents), cost:, terms:, uncovered_dimensions: [])
  end

  private

  # Normalize the candidate table into search entries carrying the candidate's
  # signature vector, its exact scale relative to base units, and its display
  # cost.
  # @param candidates [Array, Hash] see {#compact}
  # @return [Array<Hash>]
  def compact_candidate_entries(candidates)
    list = case candidates
           when Hash then candidates.map { |name, candidate_cost| [name, candidate_cost] }
           when Array then candidates.map { |name| [name, 1] }
           else raise ArgumentError, "candidates must be an Array of units or a Hash of units to display costs"
           end
    raise ArgumentError, "candidates must not be empty" if list.empty?

    list.map do |name, candidate_cost|
      unless candidate_cost.is_a?(Numeric) && !candidate_cost.is_a?(::Complex) && !candidate_cost.negative?
        raise ArgumentError, "display cost for '#{name}' must be a non-negative real number"
      end

      candidate = name.is_a?(Unit) ? name : unit_class.new(name.to_s)
      raise ArgumentError, "Cannot use temperature unit '#{name}' as a compact candidate" if candidate.temperature?

      {
        name: candidate.units,
        cost: candidate_cost,
        vector: candidate.unit_signature_vector,
        scale: candidate.to_base.scalar,
        numerator: candidate.numerator,
        denominator: candidate.denominator
      }
    end
  end

  # Depth-first search over the bounded exponent space. Candidates are
  # visited in reverse order so that, among equally cheap solutions, the first
  # one found prefers candidates listed earlier by the caller; a solution only
  # replaces the current best when it is strictly cheaper or uses fewer unit
  # symbols at the same cost.
  # @param target [Array<Integer>] signature vector of the original unit
  # @param entries [Array<Hash>] candidate entries from {#compact_candidate_entries}
  # @param max_exponent [Integer] largest absolute exponent to try
  # @return [Array<Integer>, nil] the chosen exponent per candidate, or nil
  def compact_search(target, entries, max_exponent)
    choices = (0..max_exponent).flat_map { |exponent| exponent.zero? ? [0] : [exponent, -exponent] }
    exponents = ::Array.new(entries.size, 0)
    best = nil
    search = lambda do |index, remaining, current_cost, current_terms|
      if index.negative?
        return unless remaining.all?(&:zero?)

        solution = [current_cost, current_terms, exponents.dup]
        best = solution if best.nil? || (solution[0] <=> best[0]).negative? || (solution[0] == best[0] && solution[1] < best[1])
        return
      end

      entry = entries[index]
      choices.each do |exponent|
        next_cost = current_cost + (entry[:cost] * exponent.abs)
        next_terms = current_terms + exponent.abs
        next if best && (next_cost > best[0] || (next_cost == best[0] && next_terms >= best[1]))

        exponents[index] = exponent
        search.call(index - 1, remaining.zip(entry[:vector]).map { |left, right| left - (right * exponent) }, next_cost, next_terms)
      end
      exponents[index] = 0
    end
    search.call(entries.size - 1, target, 0, 0)
    best && best[2]
  end

  # Dimensions of the target vector that no candidate contains at all
  # @param target [Array<Integer>] signature vector of the original unit
  # @param entries [Array<Hash>] candidate entries from {#compact_candidate_entries}
  # @return [Array<Symbol>]
  def compact_uncovered_dimensions(target, entries)
    SIGNATURE_VECTOR.each_with_index.filter_map do |dimension, index|
      dimension if !target[index].zero? && entries.none? { |entry| !entry[:vector][index].zero? }
    end
  end

  # Build the compacted unit from the chosen exponents, folding the combined
  # scale of the candidates exactly into the scalar
  # @param entries [Array<Hash>] candidate entries from {#compact_candidate_entries}
  # @param exponents [Array<Integer>] chosen exponent per candidate
  # @return [RubyUnits::Unit]
  def compact_build_unit(entries, exponents)
    combined_scale = 1
    exact = compact_exact_scalar? && entries.each_with_index.all? { |entry, index| exponent_exact?(entry[:scale], exponents[index]) }
    numerator = []
    denominator = []
    entries.each_with_index do |entry, index|
      exponent = exponents[index]
      next if exponent.zero?

      combined_scale *= entry[:scale]**exponent
      exponent.abs.times do
        numerator.concat(exponent.positive? ? entry[:numerator] : entry[:denominator])
        denominator.concat(exponent.positive? ? entry[:denominator] : entry[:numerator])
      end
    end
    unit_class.new(unit_class.eliminate_terms(compact_scaled_value(combined_scale, exact), numerator, denominator))
  end

  # true when the scalar of this unit is known exactly
  # @return [Boolean]
  def compact_exact_scalar?
    compact_exact_numeric?(@scalar) && compact_exact_numeric?(base_scalar)
  end

  # true when a candidate scale is known exactly or is not used
  # @return [Boolean]
  def exponent_exact?(scale, exponent)
    exponent.zero? || compact_exact_numeric?(scale)
  end

  # true when a numeric value has an exact representation
  # @return [Boolean]
  def compact_exact_numeric?(value)
    value.is_a?(Integer) || value.is_a?(Rational)
  end

  # The scalar of the compacted unit. When the original scalar and the scales
  # of every chosen candidate are exact (Integer or Rational), the conversion
  # is performed with exact rational arithmetic; otherwise the scalar keeps
  # the arithmetic semantics of its own numeric type (Float, BigDecimal, ...).
  # @param combined_scale [Rational] scale of the chosen representation in base units
  # @param exact [Boolean] whether the exact code path can be used
  # @return [Numeric]
  def compact_scaled_value(combined_scale, exact)
    if exact
      unit_class.normalize_to_i(base_scalar.to_r / combined_scale)
    else
      base_scalar / combined_scale
    end
  end
end
