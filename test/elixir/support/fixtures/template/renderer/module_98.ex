# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module98 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module3

  prop :entities, [Module3], from_query: &entities_query/0

  @impl Component
  def template do
    ~HOLO"""
    embedded = {Enum.map_join(@entities, ",", &embedded_titles/1)}
    """
  end

  defp embedded_titles(entity) do
    Enum.map_join(entity.a, "+", & &1.c)
  end

  defp entities_query do
    include(Module3, :a)
  end
end
