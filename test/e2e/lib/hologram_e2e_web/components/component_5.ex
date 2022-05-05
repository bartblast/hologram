defmodule HologramE2E.Component5 do
  use Hologram.Component

  def init(props, _conn) do
    %{
      count: props.initial_count
    }
  end

  def template do
    ~H"""
    <button id="server-initialized-component-button" on:click="increment">Increment in server-initialized component</button>
    <div id="server-initialized-component-text">server-initialized component count = {@count}</div>
    """
  end

  def action(:increment, _params, state) do
    put(state, :count, state.count + 1)
  end
end
