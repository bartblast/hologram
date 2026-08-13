defmodule HologramClusterTests.InitSubscribePage do
  use Hologram.Page

  route "/init-subscribe"

  layout HologramClusterTests.Components.DefaultLayout

  @channel {:room, :init}

  def init(_params, component, server) do
    {
      put_state(component, :received, "none"),
      put_subscription(server, @channel)
    }
  end

  def template do
    ~HOLO"""
    <p>Received: <strong id="received">{@received}</strong></p>
    """
  end

  def action(:show, params, component) do
    put_state(component, :received, params[:message])
  end
end
