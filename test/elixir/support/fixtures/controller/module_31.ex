# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module31 do
  use Hologram.Page

  alias Hologram.Auth
  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module31"

  layout LayoutFixture

  middleware :capture_actor

  def capture_actor(server, _opts) do
    put_stash(server, :actor, Auth.user_id())
  end

  @impl Page
  def init(_params, component, server) do
    put_state(component, actor: get_stash(server, :actor))
  end

  @impl Page
  def template do
    ~HOLO"actor={@actor}"
  end
end
