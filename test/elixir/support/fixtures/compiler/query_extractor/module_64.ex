# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module64 do
  # Stands for an entity type whose derived field passes a field of the row to a guarded query
  # builder, at a location the refusal names.

  alias Hologram.Entity.Derived
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module63
  alias Hologram.Test.Fixtures.Entity.Module36

  def __derived_definition__(:guarded) do
    last_read_at = Derived.field(Module36, [:last_read_at])

    Module36
    |> Derived.field([:channel, :messages])
    |> Module63.guarded(last_read_at)
    |> Derived.lower()
  end

  def __derived_locations__, do: %{guarded: {"lib/my_app/member.ex", 7}}
end
