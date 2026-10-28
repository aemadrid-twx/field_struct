# frozen_string_literal: true

module FieldStruct
  # Namespace for the built-in coercion types ({Types::String}, {Types::Integer},
  # …) and the {Types::Base} contract that custom types implement.
  module Types
    # Abstract base for all FieldStruct type classes.
    #
    # Subclasses must implement {#coerce} and {#ruby_type}. They may override
    # {#missing?} when their notion of "missing" is broader than nil-only
    # (e.g. strings consider empty/whitespace missing, arrays consider empty
    # missing).
    class Base
      # Native per-field options this type understands, as a frozen Hash of
      # option-name (Symbol) → descriptor. Each descriptor is built by
      # {.option} and carries the accepted value classes, whether the option
      # is required at declaration time, and any Symbol presets it accepts.
      #
      # This merges {.own_option_schema} down the class chain so a subtype
      # inherits its parent's options for free (e.g. {Types::UUID} picks up
      # {Types::String}'s +format:+ / +enum:+). The merged result is frozen and
      # memoized per type class — a type's option vocabulary is fixed at load,
      # so this is computed once rather than on every field declaration.
      #
      # This is the single source of truth for both *validation* (the DSL
      # checks declared values against these descriptors) and *discoverability*
      # (an agent or human can ask a type what it accepts without reading
      # source). Options *not* listed here are treated as foreign and pass
      # through onto the Field untouched, available to downstream tooling.
      #
      # @return [::Hash{::Symbol => ::Hash{::Symbol => Object}}]
      def self.option_schema
        @option_schema ||= begin
          inherited = superclass.respond_to?(:option_schema) ? superclass.option_schema : {}
          inherited.merge(own_option_schema).freeze
        end
      end

      # The options this type adds on top of its superclass's. Subclasses
      # override *this* (not {.option_schema}) to declare their native options;
      # the empty default means "adds nothing." {.option_schema} handles the
      # inheritance merge.
      #
      # @return [::Hash{::Symbol => ::Hash{::Symbol => Object}}]
      def self.own_option_schema
        {}
      end

      # Build a normalized descriptor for {.option_schema}.
      #
      # @param type [::Class, ::Array<::Class>] the Ruby class(es) a declared
      #   value may be an instance of
      # @param required [Boolean] whether the option must be present at
      #   field-declaration time
      # @param presets [::Array<::Symbol>] Symbol preset names the option also accepts
      # @return [::Hash{::Symbol => Object}] a frozen descriptor: +{ type:, required:, presets: }+
      def self.option(type:, required: false, presets: [])
        {type: ::Kernel.Array(type).freeze, required: required, presets: presets.to_a.freeze}.freeze
      end

      # Resolve symbolic preset references on the per-field options hash
      # at field-declaration time. Default implementation passes options
      # through unchanged; concrete types override to interpret their
      # own options (e.g. +format: :iso8601+ → strftime string).
      #
      # @param options [::Hash{::Symbol => Object, nil}] the per-field options hash, as written by the user
      # @return [::Hash{::Symbol => Object, nil}] possibly-modified options to store on the Field
      def self.resolve_options(options)
        options
      end

      # Resolve a declared +format:+ into the form coercion and rendering use.
      #
      # Declared options are kept exactly as the user wrote them — see
      # {TimeFormatResolver} for why — so a Symbol preset name has to be
      # expanded somewhere, and the type owning the preset table is the only
      # thing that can do it. This default serves types with no preset table:
      # a String passes through, a Symbol is refused.
      #
      # @param format [::String, ::Symbol, nil] the format as declared
      # @return [::String, nil]
      # @raise [ArgumentError] when given a Symbol and the type has no presets
      def self.resolve_format(format)
        return format if format.nil? || format.is_a?(::String)

        raise ArgumentError, "#{name || "this type"} has no format presets; got #{format.inspect}"
      end

      # Coerce an input value into the type's domain.
      #
      # The contract here is intentionally loose — subclasses override with
      # explicit kwargs for the options they consume (e.g. +format:+ for
      # Date, +round:+ for Float, +of_type:+ for Array), plus a trailing
      # +**+ catch-all so a call site that splats +field.options+ can pass
      # keys that some types ignore. See each subclass's +coerce+ for the
      # exact accepted options.
      #
      # @param value [Object] raw input — each subclass narrows this to
      #   the inputs it actually accepts
      # @return [Object] the coerced value
      # @raise [NotImplementedError] always, unless overridden by a subclass
      def coerce(value, **)
        raise NotImplementedError, "#{self.class} must implement #coerce"
      end

      # Whether the given value should be treated as "missing" for the purpose
      # of presence checks. The default is nil-only; subclasses override for
      # emptier notions.
      #
      # @param value [Object]
      # @return [Boolean]
      def missing?(value)
        value.nil?
      end

      # The native Ruby class a coerced value will be an instance of.
      # Used by the (deferred) RBS generator and for introspection.
      #
      # @return [Class]
      # @raise [NotImplementedError] always, unless overridden by a subclass
      def ruby_type
        raise NotImplementedError, "#{self.class} must implement #ruby_type"
      end

      # The RBS type expression {FieldStruct::RBS} emits for fields of this
      # type, or +nil+ (the default) to derive one from {#ruby_type}. Override
      # in a custom type whose values {#ruby_type} can't describe on its own —
      # typically a generic class, which RBS needs type arguments for:
      #
      #   def ruby_type = ::Hash
      #   def rbs_type  = '::Hash[::Symbol, ::String]'
      #
      # Without it a bare generic +ruby_type+ is emitted with +untyped+
      # arguments (+::Hash[untyped, untyped]+). A field's own +rbs_type:+
      # option wins over this. Fully qualify constants (+::Hash+, not
      # +Hash+): the RBS is emitted inside the struct's module nesting.
      #
      # @return [::String, nil]
      def rbs_type
        nil
      end

      # Concise type-instance representation. The default shows just the
      # type-class name (e.g. +#<FieldStruct::Types::String>+). Subclasses
      # that carry parameter state (Nested, Union, …) override to surface
      # what they wrap.
      #
      # @return [::String]
      def inspect
        full = self.class.name || 'AnonymousType'
        prefixed = full.sub(/\AFieldStruct\b/, FieldStruct.inspect_namespace)
        "#<#{prefixed}>"
      end

      # @param pp [Object] a PP-shaped sink (responds to +#text+)
      # @return [void]
      def pretty_print(pp)
        pp.text(inspect)
      end
    end
  end
end
