# An embedded schema that embeds itself.
defmodule HologramEcosystemTests.Ecto.Section do
  use Ecto.Schema

  alias HologramEcosystemTests.Ecto.Section

  embedded_schema do
    field :heading, :string

    embeds_many :sections, Section
  end
end
