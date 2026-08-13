defmodule HologramClusterTests.PlainPage do
  use Hologram.Page

  route "/plain"

  layout HologramClusterTests.Components.DefaultLayout

  # Declares no subscriptions, so its connection starts unbound - the page for tests
  # that grant subscriptions from outside any handler.
  def init(_params, component, _server) do
    put_state(component, :received, "none")
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
