# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module144 do
  # Stands for an entity type whose derived field calls the query builder the cover test
  # cover-compiles. The definition reads the fields of an entity type that compiles.

  alias Hologram.Entity.Derived
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module143
  alias Hologram.Test.Fixtures.Entity.Module36

  def __derived_definition__(:recent) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module143.recent(5)
    |> Derived.lower()
  end

  def __derived_locations__, do: %{recent: {"lib/my_app/member.ex", 7}}
end
