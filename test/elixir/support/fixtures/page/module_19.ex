defmodule Hologram.Test.Fixtures.Page.Module19 do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  route "/hologram-test-fixtures-page-module19"

  layout Hologram.Test.Fixtures.LayoutFixture

  derived :ripe, [Entity2], fn -> filter(Entity2, a == false) end

  @impl Page
  def template do
    ~HOLO""
  end
end
