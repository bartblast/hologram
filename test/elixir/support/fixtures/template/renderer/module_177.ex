defmodule Hologram.Test.Fixtures.Template.Renderer.Module177 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :query, :any

  derived :entities, [Entity2], fn query -> query end

  derived :names, :string, fn entities -> Enum.map_join(entities, ",", & &1.c) end

  @impl Component
  def template do
    ~HOLO"entities = {@names}"
  end
end
