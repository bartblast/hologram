# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Component.Module51 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module16, as: Entity16

  derived :entities, [Entity16], fn ->
    filter(Entity16, any(secret <- secrets, secret.token == "tok_hidden"))
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
