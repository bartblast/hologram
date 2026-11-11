# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module170 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module25, as: Entity25

  derived :entities, [Entity25], fn ->
    Entity25
    |> include(h)
    |> filter(h.title != "nothing")
    |> sort(created_at)
  end

  @impl Component
  def template do
    ~HOLO"""
    titles = {Enum.map_join(@entities, ",", &(&1.h && &1.h.title))}
    """
  end
end
