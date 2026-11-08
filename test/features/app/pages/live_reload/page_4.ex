defmodule HologramFeatureTests.LiveReload.Page4 do
  use Hologram.Page

  route "/live-reload/4"

  layout HologramFeatureTests.Components.LiveReloadDigestLayout

  state :count, :integer

  def init(_params, component, _server) do
    put_state(component, :count, 0)
  end

  def template do
    ~HOLO"""
    <h1>Live reload page 4</h1>
    <p id="styled">Styled text</p>
    <p>Count: <strong id="count">{@count}</strong></p>
    <button $click="increment">Increment</button>
    """
  end

  def action(:increment, _params, component) do
    put_state(component, :count, component.state.count + 1)
  end
end
