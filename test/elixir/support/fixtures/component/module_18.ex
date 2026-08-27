# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module18 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module15, as: Entity15

  prop :entities, [Entity15], from_query: &entities_query/0

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query do
    order_by(Entity15, :token)
  end
end
