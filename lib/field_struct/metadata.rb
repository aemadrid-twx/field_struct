# frozen_string_literal: true

module FieldStruct
  # The per-class collection of {Field} declarations.
  #
  # Mutable while a class is being defined — the DSL adds fields as it
  # encounters them — and queried thereafter by name or via iteration.
  # Subclass inheritance is handled by {#merge}: a fresh child Metadata
  # is seeded with the parent's fields, then accumulates its own; child
  # declarations win on conflict.
  class Metadata
    include Enumerable

    def initialize
      @fields = {}
      @serializations = {}
      @reverse_serializations = {}
    end

    # @return [Hash{Symbol=>Hash{Symbol=>String}}] declared
    #   external-name mappings keyed by format name. Each inner hash
    #   maps an internal field name (Symbol) to its external name
    #   (String). Fields not listed in an inner hash serialize under
    #   their canonical name.
    attr_reader :serializations

    # @param field [Field]
    # @return [self]
    def add(field)
      @fields[field.name] = field
      self
    end

    # @param name [Symbol, String]
    # @return [Field, nil]
    def [](name)
      @fields[name.to_sym]
    end

    # @return [Array<Symbol>] field names in insertion order
    def names
      @fields.keys
    end

    # Yields each {Field} in insertion order.
    #
    # @yield [field]
    # @yieldparam field [Field]
    # @return [Enumerator<Field>] when no block is given
    def each(&block)
      @fields.each_value(&block)
    end

    # A copy-pasteable schema view of the declared fields, keyed by field
    # name. Each value is a plain Hash of primitives/strings (no live type
    # objects), so the result reads cleanly in a console and is safe to
    # `pp` or dump — handy for seeing a model's shape without reading its
    # source. Option values that are classes or type instances are rendered
    # as short names; a callable default shows as +"<callable>"+.
    #
    #   User.metadata.to_h
    #   # => { name: { type: "String", ruby_type: "String", required: true,
    #   #              default: nil, options: {}, description: nil }, ... }
    #
    # When a block is given this falls back to +Enumerable#to_h+ (mapping
    # each {Field} to a pair), preserving existing callers.
    #
    # @return [Hash{Symbol=>Hash{Symbol=>Object, nil}}] field name → schema, or
    #   the block-mapped pairs when a block is supplied
    def to_h(&block)
      return super if block

      @fields.transform_values { |field| field_schema(field) }
    end

    # Record a serialization mapping for the named format. Repeats on
    # the same format name replace the prior mapping (last-write-wins).
    # The mapping is frozen on its way in.
    #
    # @param name [Symbol, String]
    # @param mapping [Hash{Symbol=>String}]
    # @return [self]
    def add_serialization(name, mapping)
      @serializations[name.to_sym] = mapping.freeze
      self
    end

    # Look up the mapping for a format. Returns an empty hash when the
    # format hasn't been declared — the implicit identity mapping that
    # serializers fall back to.
    #
    # @param name [Symbol, String]
    # @return [Hash{Symbol=>String}] frozen mapping (empty hash when undeclared)
    def serialization(name)
      @serializations[name.to_sym] || EMPTY_SERIALIZATION
    end

    # The reverse of {#serialization}: external name → field name, which
    # {Base.from_json} needs on every call. Built once per mapping and reused
    # while {#serialization} still returns that same frozen mapping, so any
    # writer that installs a new one ({#add_serialization}, {#merge}, or a
    # direct write to {#serializations}) is picked up on the next call.
    #
    # @api private
    # @param name [Symbol, String]
    # @return [Hash{String=>Symbol}] frozen; empty when the format is undeclared
    def reverse_serialization(name)
      key = name.to_sym
      mapping = serialization(key)
      cached = @reverse_serializations[key]
      return cached.last if cached && cached.first.equal?(mapping)

      reverse = mapping.each_with_object({}) { |(internal, external), out| out[external] = internal }.freeze
      # A mapping that isn't frozen could change in place, so it isn't cached.
      @reverse_serializations[key] = [mapping, reverse] if mapping.frozen?
      reverse
    end

    # The identity mapping {#serialization} returns for an undeclared format.
    # @return [Hash{Symbol=>String}]
    EMPTY_SERIALIZATION = {}.freeze
    private_constant :EMPTY_SERIALIZATION

    # Copy fields and serializations from +parent+ into self, leaving
    # already-declared entries untouched (child wins). Order: existing
    # self fields stay where they are; parent fields are appended in
    # iteration order if not present.
    #
    # @param parent [Metadata]
    # @return [self]
    def merge(parent)
      parent.each do |field|
        @fields[field.name] = field unless @fields.key?(field.name)
      end
      parent.serializations.each do |name, mapping|
        @serializations[name] = mapping unless @serializations.key?(name)
      end
      self
    end

    # Concise one-line representation. Lists the declared field names
    # and, when present, the declared serialization formats — without
    # dumping the underlying ivar hashes.
    #
    # @return [String]
    def inspect
      return "#<#{FieldStruct.inspect_namespace}::Metadata empty>" if @fields.empty?

      parts = ["fields=#{@fields.keys.inspect}"]
      parts << "serializations=#{@serializations.keys.inspect}" unless @serializations.empty?
      "#<#{FieldStruct.inspect_namespace}::Metadata #{parts.join(" ")}>"
    end

    # Multi-line representation suitable for IRB / pp. Renders each
    # field on its own indented line using {Field#inspect}, with the
    # closing +>+ on its own line.
    #
    # @param pp [Object] a PP-shaped sink (responds to +#text+)
    # @return [void]
    def pretty_print(pp)
      if @fields.empty?
        pp.text(inspect)
        return
      end

      pp.text("#<#{FieldStruct.inspect_namespace}::Metadata")
      @fields.each_value do |field|
        pp.text("\n  ")
        pp.text(field.inspect)
      end
      pp.text("\n  serializations=#{@serializations.keys.inspect}") unless @serializations.empty?
      pp.text("\n>")
    end

    # Human/agent-readable summary of the declared fields: one line each
    # with the field's type (a nested struct's class name), required-ness,
    # its +desc:+, and the native options its type
    # accepts (with value shapes, required options starred, and any presets).
    # Answers "what can I put here?" without reading source. For the
    # structured form use {#to_h}; for a class-titled version use
    # {Base.describe}.
    #
    #   name (String, required) — "Full name" — accepts format (Regexp | Symbol), enum (Array)
    #   address (Address, optional)
    #
    # @return [String]
    def describe
      return '(no fields)' if @fields.empty?

      @fields.each_value.map { |field| describe_field(field) }.join("\n")
    end

    private

    # @param field [Field]
    # @return [String] one +describe+ line for a field
    def describe_field(field)
      flags = [type_label(field), field.required? ? 'required' : 'optional']
      flags << 'sensitive' if field.sensitive?
      label = "  #{field.name} (#{flags.join(", ")})"
      parts = [label, field.description&.inspect, declared_options_summary(field), accepts_summary(field.type),
               element_accepts_summary(field)].compact

      parts.join(' — ')
    end

    # A nested struct field names its class (+Address+), not the generic
    # +Nested+, so the reader knows which class to +describe+ next. An
    # anonymous struct has no name to give, so it stays +Nested+.
    #
    # @param field [Field]
    # @return [String] the type shown in a +describe+ line
    def type_label(field)
      instance = field.type_instance
      return short_name(instance.struct_class) if instance.is_a?(FieldStruct::Types::Nested) && instance.struct_class.name

      short_name(field.type)
    end

    # What this field actually declares, as written.
    #
    # Without this, +describe+ answered only "what COULD go in this field" —
    # the type's option vocabulary — and a field declaring
    # +format: :iso8601, enum: %w[USD EUR]+ rendered identically to one
    # declaring nothing at all. The option schema belongs to the type; this
    # belongs to the field.
    #
    # @param field [Field]
    # @return [String, nil] +nil+ when the field declares no options
    def declared_options_summary(field)
      # Every temporal field carries `format: nil` from apply_default_format,
      # so nils are dropped rather than rendered as a declaration that isn't one.
      declared = field.options.compact
      return nil if declared.empty?

      declared.map { |key, value| "#{key}: #{declared_option_repr(value)}" }.join(', ')
    end

    # @return [String] a declared option value, rendered for a human. Type
    #   values (an Array field's +of_type:+) show their bare type name rather
    #   than a quoted string, so the line reads like the declaration it
    #   describes.
    # @param value [Object, nil] a declared option value
    def declared_option_repr(value)
      case value
      when FieldStruct::Types::Nested then "Nested(#{short_name(value.struct_class)})"
      when FieldStruct::Types::Base then short_name(value.class)
      when ::Class then short_name(value)
      # Spelled out rather than Hash#inspect, whose format changed in Ruby 3.4.
      when ::Hash then "{#{value.map { |key, item| "#{key}: #{declared_option_repr(item)}" }.join(", ")}}"
      else value.inspect
      end
    end

    # What an array field's +element:+ may hold — the names of its element
    # type's native options — so the line answers "what can I pass to each
    # element" too.
    #
    # @param field [Field]
    # @return [String, nil] +nil+ for a non-array field, or an element type
    #   with no options (a nested struct)
    def element_accepts_summary(field)
      return nil unless field.type <= FieldStruct::Types::Array

      # Names only: the shapes are the element type's own (its
      # +option_schema+), and repeating them doubled every array line.
      element_class = FieldStruct::Types::Array.element_class(field.options[:of_type])
      return nil unless element_class.respond_to?(:option_schema)

      names = element_class.option_schema.keys
      names.empty? ? nil : "element accepts #{names.join(", ")}"
    end

    # @return [String, nil] the type's native option vocabulary, or +nil+ when
    #   the type declares none
    # @param type_class [Class<Types::Base>]
    def accepts_summary(type_class)
      accepts = native_options_summary(type_class)
      accepts.empty? ? nil : "accepts #{accepts}"
    end

    # @return [String] the type's native options as +name(shapes)+, required
    #   ones starred, presets appended — empty when the type has none
    # @param type_class [Class<Types::Base>]
    def native_options_summary(type_class)
      return '' unless type_class.respond_to?(:option_schema)

      type_class.option_schema.map do |name, descriptor|
        shapes = descriptor[:type].map { |klass| short_name(klass) }.join(' | ')
        star = descriptor[:required] ? '*' : ''
        presets = descriptor[:presets].empty? ? '' : "; presets: #{descriptor[:presets].join(", ")}"
        "#{name}#{star} (#{shapes}#{presets})"
      end.join(', ')
    end

    # Render one field as a primitive-only schema Hash for {#to_h}.
    #
    # @param field [Field]
    # @return [Hash{Symbol=>Object, nil}]
    def field_schema(field)
      schema = {
        type: short_name(field.type),
        ruby_type: ruby_type_repr(field.type_instance.ruby_type),
        required: field.required?,
        default: schema_value(field.default),
        options: field.options.transform_values { |value| schema_value(value) },
        description: field.description
      }
      # Only when set, so the schema of a field without one is unchanged.
      schema[:rbs_type] = field.rbs_type if field.rbs_type
      schema[:sensitive] = true if field.sensitive?
      schema
    end

    # A single class, or +A | B+ for a multi-class ruby_type (boolean, union).
    #
    # @param ruby_type [Class, Array<Class>] a type's {Types::Base#ruby_type}
    # @return [String]
    def ruby_type_repr(ruby_type)
      Array(ruby_type).map(&:name).join(' | ')
    end

    # Reduce an option/default value to something printable: short class
    # names for type references, +"<callable>"+ for procs, recursion into
    # Array/Hash, everything else as-is.
    #
    # @param value [Object, nil] an option or default value
    # @return [Object, nil]
    def schema_value(value)
      case value
      when nil, true, false, ::Numeric, ::String, ::Symbol, ::Regexp, ::Range then value
      when ::Class then short_name(value)
      when FieldStruct::Types::Base then short_name(value.class)
      when ::Array then value.map { |element| schema_value(element) }
      when ::Hash then value.transform_values { |element| schema_value(element) }
      else
        value.respond_to?(:call) ? '<callable>' : value
      end
    end

    # @param klass [Module]
    # @return [String] the last segment of the class name
    def short_name(klass)
      klass.name.to_s.split('::').last
    end
  end
end
