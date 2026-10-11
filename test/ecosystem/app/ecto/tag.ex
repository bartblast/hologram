# A real Ecto schema, for the tests of what the compiler makes of one: which of its reflection
# functions a page's bundle gets.
defmodule HologramEcosystemTests.Ecto.Tag do
  use Ecto.Schema

  embedded_schema do
    field :name, :string
  end
end
