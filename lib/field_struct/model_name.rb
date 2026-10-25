# frozen_string_literal: true

module FieldStruct
  # Minimal ActiveModel::Name-shaped value for {Base.model_name}.
  #
  # We mirror only what Rails-adjacent callers commonly reach for:
  # +name+, +singular+, +plural+, +element+, and string coercion.
  # No ActiveModel code is reused; pluralization is naive +s+-suffix
  # English. If a richer Name is needed, a downstream gem can build on
  # this without changing the surface.
  class ModelName
    # @return [String] the fully-qualified class name (or "" for anonymous classes)
    attr_reader :name

    # @return [String] last segment, snake_case (e.g. "user_account")
    attr_reader :singular

    # @return [String] naive +s+-suffixed plural of {#singular} — no English
    #   rules, so +Address+ gives +"addresss"+ and +Person+ gives +"persons"+
    attr_reader :plural

    # @return [String] same as {#singular} (the AM convention for last segment)
    attr_reader :element

    # @param class_name [String, nil]
    def initialize(class_name)
      @name = class_name.to_s
      base = @name.split('::').last.to_s
      @element = camel_to_snake(base)
      @singular = @element
      @plural = "#{@element}s"
    end

    # @return [String]
    def to_s
      @name
    end

    alias to_str to_s

    private

    # @param str [String] a bare class name
    # @return [String] its snake_case form
    def camel_to_snake(str)
      str.gsub(/([a-z\d])([A-Z])/, '\\1_\\2').gsub(/([A-Z]+)([A-Z][a-z])/, '\\1_\\2').downcase
    end
  end
end
