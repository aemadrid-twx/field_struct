---
title: How to validate request params
description: Turn a controller's or API's params into a typed struct, and send its errors back as JSON.
sidebar:
  label: Validate request params
  order: 2
---

Params arrive as a Hash of strings. Declare the shape you expect once, and let
FieldStruct coerce the values and collect the errors.

## 1. Declare the params

```ruby title="signup_params.rb" run
class SignupParams < FieldStruct::Base
  unknown_attributes :raise

  required :email,      :email
  required :age,        :integer, in: (13..)
  optional :newsletter, :boolean, default: false
end
```

`unknown_attributes :raise` makes a key you didn't declare an error instead of
quietly dropping it. Leave it out where extra keys are expected and harmless.

## 2. Build it from the params

String keys work, and each value is coerced to its field's type:

```ruby run
params = { 'email' => 'ann@example.com', 'age' => '34', 'newsletter' => 'true' }

signup = SignupParams.new(params)
signup.valid?      # => true
signup.age         # => 34
signup.newsletter  # => true
```

`new` takes a Hash or anything with `to_hash`, so in a Rails controller you can
pass permitted params straight in:

```ruby
signup = SignupParams.new(params.require(:signup).permit(:email, :age, :newsletter))
```

## 3. Send the errors back

With the default coercion policy, building never raises for a bad value. Check
`valid?` and render `errors`:

```ruby run
bad = SignupParams.new('email' => 'not-an-email', 'age' => '12')

bad.valid?                 # => false
bad.errors.to_h            # => { email: ["is invalid"], age: ["is invalid"] }
bad.errors.full_messages   # => ["Email is invalid", "Age is invalid"]

require 'json'
JSON.generate(errors: bad.errors.to_h)  # => '{"errors":{"email":["is invalid"],"age":["is invalid"]}}'
```

A value that can't be coerced at all says what was expected, never what was
sent, so it's safe to return and to log:

```ruby run
SignupParams.new('email' => 'ann@example.com', 'age' => 'abc').errors[:age]  # => ["could not be coerced: Integer fields expect a base-10 integer, got a String that is not one"]
```

## 4. Rescue unknown keys

With `unknown_attributes :raise`, an extra key raises
`FieldStruct::UnknownAttributeError`. Its `keys` name the extras, never their
values:

```ruby run
error = begin
  SignupParams.new('email' => 'ann@example.com', 'age' => '34', 'admin' => 'true')
rescue FieldStruct::UnknownAttributeError => e
  e
end

error.keys     # => [:admin]
error.message  # => "unknown attribute(s) for SignupParams: :admin"
```

Put together, a controller action looks like this. The struct is the
allow-list here, so the controller hands it every key with `to_unsafe_h` and
lets `unknown_attributes :raise` reject the extras. (With `permit`, extra keys
are dropped before the struct ever sees them.)

```ruby
def create
  signup = SignupParams.new(params.require(:signup).to_unsafe_h)
  return render(json: { errors: signup.errors.to_h }, status: :unprocessable_entity) unless signup.valid?

  # ... use signup.email, signup.age ...
rescue FieldStruct::UnknownAttributeError => e
  render json: { errors: { base: ["unknown keys: #{e.keys.join(', ')}"] } }, status: :bad_request
end
```

## Through an action

An action's `input` block takes the same declarations. Bad input becomes a
`:invalid_input` failure before any step runs, and `to_api_h` gives you a
response-ready Hash:

```ruby run
class Signup < Actionable::Action
  input do
    required :email, :email
    required :age,   :integer, in: (13..)
  end
  output { required :id, :integer }

  step :create_user
  def create_user = @id = 42
end

Signup.run(**params).to_api_h(index: 0)    # => { index: 0, status: :success, id: 42, errors: {} }

result = Signup.run(email: 'ann@example.com', age: '12')
result.code                                # => :invalid_input
result.to_api_h(index: 0)                  # => { index: 0, status: :failure, id: nil, errors: { age: ["is invalid"] } }
```

:::caution
Pass params as keywords, with `**`. A Hash passed positionally is not read as
input: the action only accepts an already-built input struct there, so every
required field comes back as `"is required"`:

```ruby run
Signup.run(params).errors.to_h  # => { email: ["is required"], age: ["is required"] }
```
:::

## See also

- field_struct USAGE: [Payment and API boundaries](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md#payment-and-api-boundaries-unknown_attributes-raise), [Validation semantics](https://github.com/Paymentbox-com/field_struct/blob/v0.15.0/USAGE.md#validation-semantics-important)
- actionable USAGE: [Input](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#input), [Serializing a result](https://github.com/Paymentbox-com/actionable/blob/v1.9.0/USAGE.md#serializing-a-result)
