defmodule Hologram.Test.Fixtures.Page.Module24 do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module16, as: Entity16

  route "/hologram-test-fixtures-page-module24"

  layout Hologram.Test.Fixtures.LayoutFixture

  derived :holders, [Entity16], fn -> include(Entity16, secrets) end

  @impl Page
  def template do
    ~HOLO""
  end
end
