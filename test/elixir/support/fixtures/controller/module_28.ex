# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module28 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module28"

  layout LayoutFixture

  middleware :authenticate

  def authenticate(server, _opts) do
    server
    |> put_user_id(7)
    |> put_status(:forbidden)
  end

  @impl Page
  def template do
    ~HOLO"Module28"
  end
end
