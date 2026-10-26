# frozen_string_literal: true

module FieldStruct
  # A format-neutral view of a struct's fields, for code that exports structs
  # to another schema language. {FieldStruct::JSONSchema} is built on it, and
  # so can an Avro or Protobuf exporter in its own gem:
  #
  #   FieldStruct::Introspection.properties(Invoice).each do |property|
  #     property.key            # => "total" (the serialize name, as a String)
  #     property.field          # => the FieldStruct::Field (required?, default, …)
  #     property.node           # => what the value is, one of the node classes below
  #   end
  #
  # A node says what shape a value has and keeps the type instance and
  # options that shape came from, so nothing is lost on the way:
  #
  # * {ScalarNode}: any single value (+:string+, +:integer+, +:value+, a
  #   custom type); +type+ and +options+ hold the rest.
  # * {ArrayNode}: +element+ is the element's node, or +nil+ when the field
  #   records no element type (an array of unions, whose members aren't
  #   recorded; an array of arrays has an element {ArrayNode} whose own
  #   +element+ is +nil+). It is built when first read, so an exporter that
  #   uses a field-level override never instantiates the element type.
  # * {UnionNode}: +members+ are the member types' nodes, in declared order.
  # * {StructNode}: a nested struct. +klass+ is a reference, never expanded,
  #   so a recursive struct is the exporter's to handle (for example with
  #   {.named?} and a definitions table).
  #
  # Policy stays with the exporter: what +null+ means, which defaults to
  # write, how overrides work. {.node} builds the node for a type and
  # options of your own.
  #
  # +options+ are the struct's own option hashes, frozen but not deeply:
  # treat them as read-only (changing an +enum:+ Array would change what the
  # struct accepts).
  module Introspection
    # One field of a struct, as an exporter sees it.
    class Property
      # @return [Field]
      attr_reader :field
      # @return [::String] the field's name in the chosen serialization
      attr_reader :key
      # @return [ScalarNode, ArrayNode, UnionNode, StructNode]
      attr_reader :node

      # @param field [Field]
      # @param key [::String]
      # @param node [ScalarNode, ArrayNode, UnionNode, StructNode]
      def initialize(field, key, node)
        @field = field
        @key = key
        @node = node
        freeze
      end
    end

    # A single value: any type that isn't an array, union or nested struct.
    class ScalarNode
      # @return [Types::Base]
      attr_reader :type
      # @return [Hash{Symbol=>Object}] the options the value is checked with
      attr_reader :options

      # @param type [Types::Base]
      # @param options [Hash{Symbol=>Object}]
      def initialize(type, options)
        @type = type
        @options = options
        freeze
      end
    end

    # An array.
    class ArrayNode
      # @return [Types::Array]
      attr_reader :type
      # @return [Hash{Symbol=>Object}] the options this array was declared
      #   with (+{}+ for an array that is an element or a union member)
      attr_reader :options

      # @param type [Types::Array]
      # @param options [Hash{Symbol=>Object}]
      # @param element [Proc] builds the element node on first read
      def initialize(type, options, element)
        @type = type
        @options = options
        @build_element = element
        @memo = {}
        freeze
      end

      # @return [ScalarNode, ArrayNode, UnionNode, StructNode, nil] each
      #   element's node, or +nil+ when no element type is recorded
      def element
        @memo.fetch(:element) { @memo[:element] = @build_element.call }
      end
    end

    # A union: the value is one of the members.
    class UnionNode
      # @return [Types::Union]
      attr_reader :type
      # @return [::Array<ScalarNode, ArrayNode, UnionNode, StructNode>]
      attr_reader :members

      # @param type [Types::Union]
      # @param members [::Array<ScalarNode, ArrayNode, UnionNode, StructNode>]
      def initialize(type, members)
        @type = type
        @members = members.freeze
        freeze
      end
    end

    # A nested struct, by reference.
    class StructNode
      # @return [Types::Nested]
      attr_reader :type
      # @return [Class<FieldStruct::Base>]
      attr_reader :klass

      # @param type [Types::Nested]
      # @param klass [Class<FieldStruct::Base>]
      def initialize(type, klass)
        @type = type
        @klass = klass
        freeze
      end
    end

    # The fields of +klass+, in declaration order.
    #
    # @param klass [Class<FieldStruct::Base>]
    # @param serialization [Symbol] the +serialize+ format whose names
    #   become each property's +key+ (an undeclared format keeps the field
    #   names, as its serializer does)
    # @return [::Array<Property>]
    def self.properties(klass, serialization: :json)
      names = klass.metadata.serialization(serialization)
      klass.metadata.map do |field|
        Property.new(field, (names[field.name] || field.name).to_s, node(field.type_instance, field.options))
      end
    end

    # The node for a value of +type+ checked with +options+.
    #
    # @param type [Types::Base]
    # @param options [Hash{Symbol=>Object}]
    # @return [ScalarNode, ArrayNode, UnionNode, StructNode]
    def self.node(type, options = {})
      case type
      when FieldStruct::Types::Array then ArrayNode.new(type, options, -> { element_node(options) })
      when FieldStruct::Types::Union then UnionNode.new(type, type.member_types.map { |member| node(member) })
      when FieldStruct::Types::Nested then StructNode.new(type, type.struct_class)
      else ScalarNode.new(type, options)
      end
    end

    # @param options [Hash{Symbol=>Object}] an array field's options
    # @return [ScalarNode, ArrayNode, UnionNode, StructNode, nil]
    def self.element_node(options)
      of_type = options[:of_type]
      # An array of unions records only the Union class, not its members
      # (so even a Union subclass's #json_schema isn't reachable here).
      return nil if of_type.nil? || (of_type.is_a?(::Class) && of_type <= FieldStruct::Types::Union)

      node(of_type.is_a?(::Class) ? of_type.new : of_type, options[:element] || {})
    end
    private_class_method :element_node

    # Whether +klass+ has a name an exporter can use as a definition key or
    # title. A class under an anonymous module has a name, but one that reads
    # +"#<Module:0x…>::Addr"+.
    #
    # @param klass [Class]
    # @return [Boolean]
    def self.named?(klass)
      !klass.name.nil? && !klass.name.include?('#<')
    end
  end
end
