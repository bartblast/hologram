# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module111 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module25, as: Entity25

  prop :entities, [Entity25], from_query: &entities_query/0

  @impl Component
  def template do
    ~HOLO"""
    titles = {Enum.map_join(@entities, ",", &(&1.h && &1.h.title))}
    """
  end

  defp entities_query do
    Entity25
    |> include(h)
    |> filter(h.title != "nothing")
    |> order_by(created_at)
  end
end
