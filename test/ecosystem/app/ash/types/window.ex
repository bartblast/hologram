# A type of the app's own, over a type of the data framework: the rules follow what it casts to.
defmodule HologramEcosystemTests.Ash.Types.Window do
  use Ash.Type.NewType,
    subtype_of: :map,
    constraints: [
      fields: [
        from: [type: :utc_datetime],
        to: [type: :utc_datetime]
      ]
    ]
end
