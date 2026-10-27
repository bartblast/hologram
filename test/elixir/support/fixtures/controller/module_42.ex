# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module42 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module42"

  layout LayoutFixture

  @impl Page
  def init(_params, _component, server) do
    put_response_header(server, "content-type", "text/csv")
  end

  @impl Page
  def template do
    ~HOLO"Module42"
  end
end
