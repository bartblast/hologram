# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module37 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module37"

  layout LayoutFixture

  @impl Page
  def init(_params, _component, server) do
    put_response_header(server, "cache-control", "no-store")
  end

  @impl Page
  def template do
    ~HOLO"Module37"
  end
end
