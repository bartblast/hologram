# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module47 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module47"

  layout LayoutFixture

  middleware :deny

  def deny(server, _opts) do
    server
    |> put_response_header("content-security-policy", "default-src 'none'")
    |> put_response_body("denied")
    |> put_status(:forbidden)
  end

  @impl Page
  def template do
    ~HOLO"Module47"
  end
end
