defmodule Hologram.Test.Fixtures.Controller.Module18 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module18"

  layout LayoutFixture

  @impl Page
  def init(_params, component, server) do
    put_state(component, observed_cid: server.cid)
  end

  @impl Page
  def template do
    ~HOLO"observed_cid={@observed_cid}"
  end
end
