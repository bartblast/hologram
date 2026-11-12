# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module77 do
  # Stands for an entity type whose derived fields call query builders of its own the build can't
  # take a definition from, at locations the refusals name. The definitions read the fields of
  # entity types that compile.

  import Hologram.Query, only: [filter: 2]

  alias Hologram.Entity.Derived
  alias Hologram.Test.Fixtures.Entity.Module33
  alias Hologram.Test.Fixtures.Entity.Module36

  # The definitions call builders whose results no definition takes, which is what the walk
  # refuses - so their calls fail on purpose.
  @dialyzer {:nowarn_function, __derived_definition__: 1}

  def __derived_definition__(:counted) do
    Module36
    |> Derived.field([:channel, :messages])
    |> message_total()
    |> Derived.lower()
  end

  def __derived_definition__(:every_message) do
    Derived.lower(every_message())
  end

  def __derived_locations__ do
    %{
      counted: {"lib/my_app/member.ex", 7},
      every_message: {"lib/my_app/member.ex", 9}
    }
  end

  defp every_message, do: filter(Module33, position > 0)

  defp message_total(_messages), do: 3
end
