# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module19 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module16, as: Entity16

  prop :entities, [Entity16], from_query: &entities_query/0

  @impl Component
  def template do
    ~HOLO""
  end

  defp entities_query do
    include(Entity16, :secrets, &filter(&1, token: "tok_hidden"))
  end
end
