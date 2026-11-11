defmodule Hologram.Test.Fixtures.Template.Renderer.Module157 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyEntity

  derived :entities, [PolicyEntity], fn -> sort(PolicyEntity, priority) end

  @impl Component
  def template do
    ~HOLO"""
    entities = {Enum.map_join(@entities, ",", &Integer.to_string(&1.priority))}
    """
  end
end
