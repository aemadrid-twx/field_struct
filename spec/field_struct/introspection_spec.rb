# frozen_string_literal: true

RSpec.describe FieldStruct::Introspection do
  # Build a named FieldStruct subclass without leaking a top-level constant.
  def struct(const_name, &body)
    klass = Class.new(FieldStruct::Base)
    klass.class_eval(&body) if body
    stub_const(const_name, klass)
    klass
  end

  def node_for(klass, name)
    described_class.properties(klass).find { |property| property.field.name == name }.node
  end

  describe '.properties' do
    it 'lists every field in declaration order, keyed by its serialize name' do
      klass = struct('Contact') do
        required :first_name, :string
        optional :last_name, :string
        serialize :json, first_name: 'firstName'
      end

      properties = described_class.properties(klass)

      expect(properties.map(&:key)).to eq(%w[firstName last_name])
      expect(properties.map(&:field)).to eq(klass.metadata.to_a)
      expect(described_class.properties(klass, serialization: :other).map(&:key)).to eq(%w[first_name last_name])
      expect(properties).to all(be_frozen)
    end
  end

  describe '.node' do
    it 'keeps a scalar type with the options it is checked with' do
      klass = struct('Plan') { required :tier, :symbol, enum: %i[free pro] }

      node = node_for(klass, :tier)

      expect(node).to be_a(described_class::ScalarNode)
      expect(node.type).to be_a(FieldStruct::Types::Symbol)
      expect(node.options).to include(enum: %i[free pro])
    end

    it "gives an array its element's node, with the element: options" do
      klass = struct('Scores') { required :counts, :array, of: :integer, element: {in: 1..5} }

      node = node_for(klass, :counts)

      expect(node).to be_a(described_class::ArrayNode)
      expect(node.element).to be_a(described_class::ScalarNode)
      expect(node.element.type).to be_a(FieldStruct::Types::Integer)
      expect(node.element.options).to eq(in: 1..5)
    end

    it 'records no element for an array of unions, and an empty array node for an array of arrays' do
      klass = struct('Odd') do
        optional :grid, :array, of: :array
        optional :mixed, :array, of: :union
      end

      expect(node_for(klass, :mixed).element).to be_nil
      grid = node_for(klass, :grid)
      expect(grid.element).to be_a(described_class::ArrayNode)
      expect(grid.element.element).to be_nil
    end

    it 'builds an element only when it is read' do
      klass = struct('Shielded') { optional :xs, :array, of: FieldStruct::Types::Nested, json_schema: {'type' => 'array'} }

      node = node_for(klass, :xs)

      expect { node.element }.to raise_error(ArgumentError)
      expect(klass.to_json_schema['properties']['xs']).to eq('type' => %w[array null])
    end

    it "lists a union's members in declared order" do
      klass = struct('Either') { required :id, :union, of: %i[integer string array] }

      node = node_for(klass, :id)

      expect(node).to be_a(described_class::UnionNode)
      expect(node.members.map(&:class)).to eq(
        [described_class::ScalarNode, described_class::ScalarNode, described_class::ArrayNode]
      )
      expect(node.members.first.type).to be_a(FieldStruct::Types::Integer)
    end

    it 'refers to a nested struct without expanding it, so recursion stops' do
      tree = struct('Tree') { required :label, :string }
      tree.optional :children, :array, of: tree

      element = node_for(tree, :children).element

      expect(element).to be_a(described_class::StructNode)
      expect(element.klass).to equal(tree)
    end
  end

  describe '.named?' do
    it 'accepts a named class and refuses anonymous ones' do
      named = struct('Billing::Invoice')
      under_anonymous = Module.new.const_set(:Addr, Class.new(FieldStruct::Base))

      expect(described_class.named?(named)).to be(true)
      expect(described_class.named?(Class.new(FieldStruct::Base))).to be(false)
      expect(described_class.named?(under_anonymous)).to be(false)
    end
  end
end
