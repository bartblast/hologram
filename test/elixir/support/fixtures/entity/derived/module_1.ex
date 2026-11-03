# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Derived.Module1 do
  # Stands for an entity type whose derived field can't be built - a definition function refusing
  # what it reads, at a location the refusal names.

  def __derived_definition__(:broken) do
    raise ArgumentError, message: "unknown relationship :nothing"
  end

  def __derived_locations__, do: %{broken: {"lib/my_app/channel.ex", 7}}
end
