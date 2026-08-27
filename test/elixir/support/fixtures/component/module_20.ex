# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module20 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module15, as: Entity15

  prop :entities, [Entity15], from_query: &entities_query/0

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query do
    Entity15
    |> filter(label: "Report")
    |> order_by(:label)
  end
end
