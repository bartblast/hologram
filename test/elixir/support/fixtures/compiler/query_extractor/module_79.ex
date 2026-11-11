# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module79 do
  # A query builder derived fields call.

  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  def entity_type, do: Entity2

  def wanted(wanted), do: filter(Entity2, a == ^wanted)
end
