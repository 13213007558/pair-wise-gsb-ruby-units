# frozen_string_literal: true

module RubyUnits
  module Ucum
    # Minimal AST produced by {Parser}. Nodes are plain value objects used both
    # for semantic conversion and for canonical serialization (which preserves
    # annotations that are dropped by the Unit representation).
    module Nodes
      # A prefix/unit atom, a numeric factor, or a grouped term.
      class Atom
        # @return [Hash{Symbol => Object}] descriptor from {CodeTables}
        attr_reader :descriptor

        # @return [String, nil] explicit decimal prefix code (for example +k+)
        attr_reader :prefix

        # @return [String] source code of the atom
        attr_reader :code

        # @return [Integer] source position of the atom
        attr_reader :position

        # @param descriptor [Hash]
        # @param code [String]
        # @param position [Integer]
        # @param prefix [String, nil]
        def initialize(descriptor:, code:, position:, prefix: nil)
          @descriptor = descriptor
          @code = code
          @position = position
          @prefix = prefix
        end
      end

      # An atom, factor, or group together with its integer exponent and any
      # trailing UCUM annotation (+{...}+).
      class Component
        # @return [Atom, Term]
        attr_reader :base

        # @return [Integer]
        attr_reader :exponent

        # @return [String, nil]
        attr_reader :annotation

        # @return [Integer]
        attr_reader :position

        # @param base [Atom, Term]
        # @param exponent [Integer]
        # @param position [Integer]
        # @param annotation [String, nil]
        def initialize(base:, exponent:, position:, annotation: nil)
          @base = base
          @exponent = exponent
          @position = position
          @annotation = annotation
        end
      end

      # A product or quotient of components. +signed+ records which components
      # appear in the denominator.
      class Term
        # @return [Array<Component>]
        attr_reader :components

        # @return [Array<Boolean>] denominator flag for each component
        attr_reader :denominators

        # @return [Integer]
        attr_reader :position

        # @return [String] grouping delimiter (+()+ or +[]+)
        attr_reader :bracket

        # @param components [Array<Component>]
        # @param denominators [Array<Boolean>]
        # @param position [Integer]
        # @param bracket [String]
        def initialize(components:, denominators:, position: 0, bracket: "(")
          @components = components
          @denominators = denominators
          @position = position
          @bracket = bracket
        end
      end
    end
  end
end
