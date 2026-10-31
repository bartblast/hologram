# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module45 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module45"

  layout LayoutFixture

  @impl Page
  def init(_params, component, server) do
    server =
      server
      |> put_user_id(7)
      |> put_response_header("cache-control", "private, max-age=60")

    {component, server}
  end

  @impl Page
  def template do
    ~HOLO"Module45"
  end
end
