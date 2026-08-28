defmodule HologramFeatureTests.Components.Rendering.PropsOnStructComponent do
  use Hologram.Component

  prop :count, :integer

  def init(_props, component, _server) do
    put_state(component, :result, nil)
  end

  def init(_props, component) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      Component prop count: <strong id="{@cid}_prop_count">{@count}</strong>
    </p>
    <p>
      <button id="{@cid}_read_prop" $click="read_prop">Read prop</button>
    </p>
    <p>
      Component result: <strong id="{@cid}_result">{inspect(@result)}</strong>
    </p>
    """
  end

  # Reads the prop off the struct rather than from a copy kept in state, which is what makes the
  # value the one the latest render passed rather than the one the component mounted with.
  def action(:read_prop, _params, component) do
    put_state(component, :result, component.props.count)
  end
end
