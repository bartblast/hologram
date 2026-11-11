defmodule Hologram.Test.Fixtures.Template.Renderer.Module149 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  derived :entities, [Entity2], fn ->
    Entity2
    |> filter(a == true)
    |> sort(c)
  end

  derived :names, :string, fn entities -> Enum.map_join(entities, ",", & &1.c) end

  @impl Component
  def template do
    ~HOLO"entities = {@names}"
  end
end
