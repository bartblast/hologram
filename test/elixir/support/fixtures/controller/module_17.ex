defmodule Hologram.Test.Fixtures.Controller.Module17 do
  use Hologram.Component

  @impl Component
  def init(_props, component, server) do
    {component, put_subscription(server, :room_component)}
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
