# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module56 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module56"

  layout LayoutFixture

  middleware :authenticate

  def authenticate(server, _opts) do
    put_status(%{server | user_id: false}, :forbidden)
  end

  @impl Page
  def init(_params, _component, _server) do
    raise "init must not run when middleware produces a terminal response"
  end

  @impl Page
  def template do
    ~HOLO"Module56"
  end
end
