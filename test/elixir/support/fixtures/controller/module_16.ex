defmodule Hologram.Test.Fixtures.Controller.Module16 do
  use Hologram.Component

  alias Hologram.UI.Runtime

  @impl Component
  def init(_props, component, server) do
    {component, put_subscription(server, :room_layout)}
  end

  @impl Component
  def template do
    ~HOLO"""
    <Runtime />
    <slot />
    """
  end
end
