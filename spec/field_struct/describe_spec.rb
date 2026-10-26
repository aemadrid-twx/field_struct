# frozen_string_literal: true

# Human/agent-readable schema summary: fields, types, required-ness, and the
# native options each field's type accepts (design invariant 7 — "what can I
# put here" in one call). See FieldStruct::Base.describe / Metadata#describe.
RSpec.describe 'FieldStruct::Base.describe' do
  let(:klass) do
    Class.new(FieldStruct::Base) do
      required :name, :string
      optional :age, :integer
      required :tags, :array, of: :string
    end
  end

  it 'starts with the class name as a header' do
    stub_const('Person', klass)
    expect(Person.describe).to start_with("Person\n")
  end

  it 'falls back to a placeholder name for anonymous classes' do
    expect(klass.describe).to start_with('AnonymousFieldStruct')
  end

  it 'lists each field with its type and required-ness' do
    out = klass.describe
    expect(out).to include('name (String, required)')
    expect(out).to include('age (Integer, optional)')
  end

  it 'shows the accepted native options for each field type' do
    out = klass.describe
    expect(out).to match(/name .*accepts.*format.*enum/)
    expect(out).to match(/age .*accepts.*in /)
  end

  it 'marks required options with a star (array of:)' do
    expect(klass.describe).to match(/tags .*of\* /)
  end

  it 'lists a type option preset names when present' do
    uuid_klass = Class.new(FieldStruct::Base) { required :id, :uuid }
    expect(uuid_klass.describe).to match(/presets:.*v4/)
  end

  describe 'Metadata#describe' do
    it 'returns the field lines without the class header' do
      body = klass.metadata.describe
      expect(body).to include('name (String, required)')
      expect(body).not_to include('AnonymousFieldStruct')
    end

    it 'handles a class with no fields' do
      empty = Class.new(FieldStruct::Base)
      expect(empty.metadata.describe).to eq('(no fields)')
    end
  end
end

# `describe` answered "what COULD go in this field" and never "what does this
# field actually say". A field declaring `format: :iso8601, enum: %w[USD EUR]`
# rendered identically to one declaring nothing — the option schema is a
# property of the TYPE, not of the field. For a surface whose whole job is to
# explain a class without reading its source (invariant 7), that is the wrong
# half of the answer.
RSpec.describe FieldStruct::Base, 'describe renders declared options' do
  let(:klass) do
    Class.new(described_class) do
      required :on, :date, format: :iso8601
      required :code, :string, format: /\A[A-Z]{3}\z/, enum: %w[USD EUR]
      optional :qty, :integer, in: (1..10)
      optional :note, :string
    end
  end

  it 'shows a declared preset by name' do
    expect(klass.describe).to match(/on \(Date, required\) — format: :iso8601/)
  end

  it 'shows a declared enum and regexp format' do
    line = klass.describe.lines.find { |l| l.include?('code') }

    expect(line).to include('enum: ["USD", "EUR"]')
    expect(line).to include('format: /\A[A-Z]{3}\z/')
  end

  it 'shows a declared range' do
    expect(klass.describe).to match(/qty \(Integer, optional\) — in: 1\.\.10/)
  end

  # Every temporal field carries `format: nil` internally, because
  # `apply_default_format` merges the type's default in at declaration. Rendering
  # that would put a lie on the line.
  it 'says nothing for a field that declared nothing' do
    line = klass.describe.lines.find { |l| l.include?('note') }

    expect(line).not_to include('format:')
  end

  it 'omits a nil default_format on a temporal field with no declared format' do
    plain = Class.new(described_class) { required :at, :datetime }

    expect(plain.describe).not_to include('format:  —')
    expect(plain.describe).not_to match(/format: nil/)
  end

  # The type's option vocabulary is still there — it answers a different and
  # still-useful question. Declared first, because it is what the field IS.
  it 'keeps the accepts summary alongside' do
    expect(klass.describe).to match(/on \(Date, required\) — format: :iso8601 — accepts format \(/)
  end
end

# Agents read `describe` to learn a model without opening its source. It
# dropped the field's `desc:` (the one line written for exactly that reader)
# and showed a nested struct field as a bare "Nested", hiding which class to
# describe next.
RSpec.describe 'FieldStruct::Base.describe: descriptions and nested classes' do
  before do
    stub_const('Address', Class.new(FieldStruct::Base) { required :city, :string })
    stub_const('Customer', Class.new(FieldStruct::Base) do
      required :name, :string, desc: 'Full legal name'
      optional :address, Address
      optional :nickname, :string
    end)
  end

  it "shows the field's description after its type" do
    expect(Customer.describe).to include('name (String, required) — "Full legal name" — accepts')
  end

  it 'leaves the line unchanged for a field without a description' do
    expect(Customer.describe).to match(/^  nickname \(String, optional\) — accepts/)
  end

  it 'names the nested struct class so the reader knows what to describe next' do
    expect(Customer.describe).to include('address (Address, optional)')
  end

  it 'still says Nested for an anonymous nested struct' do
    anon = Class.new(FieldStruct::Base) { required :x, :integer }
    holder = Class.new(FieldStruct::Base) { optional :inner, anon }
    expect(holder.describe).to include('inner (Nested, optional)')
  end
end
