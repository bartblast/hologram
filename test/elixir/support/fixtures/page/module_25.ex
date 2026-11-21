defmodule Hologram.Test.Fixtures.Page.Module25 do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  route "/hologram-test-fixtures-page-module25"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO""
  end

  # Server code: a query here never runs in the browser, so the build leaves it to the server.
  @impl Page
  def command(:read, _params, server) do
    _rows = filter(Entity2, nonexistent == true)
    server
  end
end
