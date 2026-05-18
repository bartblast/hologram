defmodule Hologram.Test.Fixtures.Controller.Module15 do
  use Hologram.Page

  route "/hologram-test-fixtures-controller-module15"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, _component, server) do
    server = put_subscription(server, :room_a)
    raise "boom"
    server
  end

  @impl Page
  def template do
    ~HOLO""
  end
end
