# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module108 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyEntity

  prop :entities, [PolicyEntity], from_query: &entities_query/0

  @impl Component
  def template do
    ~HOLO"""
    entities = {Enum.map_join(@entities, ",", &Integer.to_string(&1.priority))}
    """
  end

  defp entities_query do
    order_by(PolicyEntity, :priority)
  end
end
