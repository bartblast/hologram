defmodule Hologram.Test.Fixtures.Template.Renderer.Module150 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :min_b, :integer

  derived :total, :integer, fn min_b ->
    Entity2
    |> filter(b > ^min_b)
    |> count()
  end

  @impl Component
  def template do
    ~HOLO"total = {@total}"
  end
end
