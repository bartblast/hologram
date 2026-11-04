# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module76 do
  # Stands for an entity type whose derived fields call query builders that run a helper of another
  # module. The definitions read the fields of an entity type that compiles.

  alias Hologram.Entity.Derived
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module75
  alias Hologram.Test.Fixtures.Entity.Module36

  def __derived_definition__(:capped) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module75.capped()
    |> Derived.lower()
  end

  def __derived_definition__(:capped_in_closure) do
    Module36
    |> Derived.field([:channel, :messages])
    |> Module75.capped_in_closure()
    |> Derived.lower()
  end

  def __derived_locations__ do
    %{
      capped: {"lib/my_app/member.ex", 7},
      capped_in_closure: {"lib/my_app/member.ex", 9}
    }
  end
end
