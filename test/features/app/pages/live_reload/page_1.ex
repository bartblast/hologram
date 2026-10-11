defmodule HologramFeatureTests.LiveReload.Page1 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.LiveReload.Page2

  route "/live-reload/1"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :count, 0)
  end

  def template do
    ~HOLO"""
    <h1>Live reload page 1</h1>
    <p>Count: <strong id="count">{@count}</strong></p>
    <button $click="increment">Increment</button>
    <Link to={Page2}>Page 2 link</Link>
    """
  end

  def action(:increment, _params, component) do
    put_state(component, :count, component.state.count + 1)
  end
end
