# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module166 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module3

  derived :entities, [Module3], fn -> include(Module3, a) end

  @impl Component
  def template do
    ~HOLO"""
    embedded = {Enum.map_join(@entities, ",", &embedded_titles/1)}
    """
  end

  defp embedded_titles(entity) do
    Enum.map_join(entity.a, "+", & &1.c)
  end
end
