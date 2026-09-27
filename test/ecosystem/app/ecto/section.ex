# An embedded schema that embeds itself, for the test that the data flow rules' records of it end.
defmodule HologramEcosystemTests.Ecto.Section do
  use Ecto.Schema

  alias HologramEcosystemTests.Ecto.Section

  embedded_schema do
    field :heading, :string

    embeds_many :sections, Section
  end
end
