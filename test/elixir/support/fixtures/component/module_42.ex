# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module42 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module15, as: Entity15

  derived :entities, [Entity15], fn ->
    Entity15
    |> filter(label: "Report")
    |> sort(label)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
