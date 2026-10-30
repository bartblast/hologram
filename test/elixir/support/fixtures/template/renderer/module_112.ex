# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module112 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module8, as: PolicyModule8

  prop :chained, [PolicyModule8], from_query: &chained_query/0
  prop :entities, [PolicyModule1], from_query: &entities_query/0

  @impl Component
  def template do
    ~HOLO"""
    parents = {Enum.map_join(@entities, ",", &inspect(&1.parent))}
    """
  end

  defp chained_query do
    order_by(PolicyModule8, created_at)
  end

  defp entities_query do
    PolicyModule1
    |> filter(public == true)
    |> order_by(priority)
  end
end
