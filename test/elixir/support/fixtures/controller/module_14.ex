defmodule Hologram.Test.Fixtures.Controller.Module14 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Controller.Module16
  alias Hologram.Test.Fixtures.Controller.Module17

  route "/hologram-test-fixtures-controller-module14"

  layout Module16

  @impl Page
  def init(_params, component, server) do
    {component, put_subscription(server, :room_page)}
  end

  @impl Page
  def template do
    ~HOLO"""
    <Module17 cid="my_component" />
    """
  end
end
