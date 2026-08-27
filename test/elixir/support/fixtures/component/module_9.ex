# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module9 do
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  def shared_query do
    filter(Entity2, a: true)
  end
end
