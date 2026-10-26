# frozen_string_literal: true

require 'oj'
require 'pathname'
require_relative 'field_struct/version'
require_relative 'field_struct/error'
require_relative 'field_struct/model_name'
require_relative 'field_struct/types/base'
require_relative 'field_struct/types/preset_resolver'
require_relative 'field_struct/types/temporal_parser'
require_relative 'field_struct/types/rfc3339_format'
require_relative 'field_struct/types/time_format_resolver'
require_relative 'field_struct/types/zone_option'
require_relative 'field_struct/types/string'
require_relative 'field_struct/types/immutable_string'
require_relative 'field_struct/types/integer'
require_relative 'field_struct/types/float'
require_relative 'field_struct/types/big_decimal'
require_relative 'field_struct/types/boolean'
require_relative 'field_struct/types/date'
require_relative 'field_struct/types/time'
require_relative 'field_struct/types/datetime'
require_relative 'field_struct/types/value'
require_relative 'field_struct/types/array'
require_relative 'field_struct/types/nested'
require_relative 'field_struct/types/symbol'
require_relative 'field_struct/types/uuid'
require_relative 'field_struct/types/url'
require_relative 'field_struct/types/email'
require_relative 'field_struct/types/union'
require_relative 'field_struct/types/binary'
require_relative 'field_struct/registry'
require_relative 'field_struct/field'
require_relative 'field_struct/metadata'
require_relative 'field_struct/errors'
require_relative 'field_struct/base'
require_relative 'field_struct/rbs'
require_relative 'field_struct/introspection'
require_relative 'field_struct/json_schema'
require_relative 'field_struct/json_schema/pattern'
require_relative 'field_struct/scaffold'

# Typed PORO foundation: declare fields with enforced types, presence checks,
# and per-field validation. Subclass {FieldStruct::Base} to get a value object
# whose attributes coerce, validate on assignment, and introspect cleanly.
module FieldStruct
  # What {Base#inspect} renders in place of a +sensitive: true+ field's
  # value (the placeholder ActiveSupport's parameter filter uses).
  #
  # @return [String]
  FILTERED = '[FILTERED]'

  # The library's root directory — the parent of +lib/+. Computed from this
  # file's location, so it resolves to the repo root in development and to the
  # installed gem directory when packaged.
  #
  #   FieldStruct.root.join('lib', 'field_struct.rb') # => #<Pathname …>
  #
  # @return [Pathname] absolute path to the gem root
  def self.root
    @root ||= Pathname.new(File.expand_path('..', __dir__))
  end

  # Build a new {Registry}, parented to +parent+ (defaults to
  # {FieldStruct.types}), and optionally configure it with a block
  # evaluated in the new registry's instance scope.
  #
  #   module Acme
  #     def self.field_types
  #       @field_types ||= FieldStruct.new_registry do
  #         register :money, Acme::Types::Money
  #       end
  #     end
  #   end
  #
  # Equivalent to the longhand:
  #
  #   FieldStruct::Registry.new(FieldStruct.types).tap do |r|
  #     r.register :money, Acme::Types::Money
  #   end
  #
  # Pass +parent: nil+ for an unparented registry (no fallback chain).
  #
  # @param parent [Registry, nil] the parent registry; defaults to
  #   {FieldStruct.types}. Pass +nil+ explicitly for no parent.
  # @yield evaluated in the new registry's instance scope, so methods
  #   like +register+ / +lookup+ / +key?+ work without an explicit receiver
  # @return [Registry]
  def self.new_registry(parent = types, &block)
    registry = Registry.new(parent)
    registry.instance_eval(&block) if block
    registry
  end

  # The base type registry, seeded with every v1 scalar type and the
  # +:decimal+ alias for +:big_decimal+. Namespace registries should be
  # built with this as their parent (see {Registry}).
  #
  # @return [Registry]
  def self.types
    @types ||= Registry.new.tap do |r|
      r.register :string, Types::String
      r.register :immutable_string, Types::ImmutableString
      r.register :integer, Types::Integer
      r.register :float, Types::Float
      r.register :big_decimal, Types::BigDecimal
      r.register :decimal, :big_decimal
      r.register :boolean, Types::Boolean
      r.register :date, Types::Date
      r.register :time, Types::Time
      r.register :datetime, Types::DateTime
      r.register :value, Types::Value
      r.register :array, Types::Array
      r.register :symbol, Types::Symbol
      r.register :uuid, Types::UUID
      r.register :url, Types::URL
      r.register :email, Types::Email
      r.register :union, Types::Union
      r.register :binary, Types::Binary
    end
  end

  # Opt-in short alias for the +FieldStruct+ module.
  #
  # Defines a top-level constant (default: +FS+) that points back to
  # +FieldStruct+, *and* swaps the prefix used by every +#inspect+
  # method in the library so IRB output reads with the short name too:
  #
  #   FieldStruct.use_alias!
  #   FS::Base                 # => FieldStruct::Base
  #   User.metadata.inspect    # => "#<FS::Metadata fields=[...]>"
  #
  # Off by default — the user has to ask for it. Idempotent. If the
  # chosen constant is already defined to something other than
  # FieldStruct, raises +NameError+ rather than clobbering.
  #
  # @param name [Symbol] the top-level constant to define (default +:FS+)
  # @return [self] for chaining
  # @raise [NameError] when the constant already points at something else
  def self.use_alias!(name = :FS)
    sym = name.to_sym
    if Object.const_defined?(sym, false)
      existing = Object.const_get(sym)
      unless existing.equal?(self)
        raise ::NameError, "::#{sym} is already defined (#{existing.inspect}); not aliasing FieldStruct"
      end
    else
      Object.const_set(sym, self)
    end
    @short_alias = sym.to_s
    self
  end

  # The current prefix that library +#inspect+ methods should render.
  # Defaults to +"FieldStruct"+; flipped to the alias string (e.g.
  # +"FS"+) by {.use_alias!}.
  #
  # @return [String]
  def self.inspect_namespace
    @short_alias || 'FieldStruct'
  end
end
