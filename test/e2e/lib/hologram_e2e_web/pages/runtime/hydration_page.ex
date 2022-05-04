defmodule HologramE2E.Runtime.HydrationPage do
  use Hologram.Page

  route "/e2e/runtime/hydration"

  def init(_params, _conn) do
    %{
      count: 100
    }
  end

  def template do
    ~H"""
    <button id="button" on:click="increment">Increment</button>
    <div id="text">count = {@count}</div>
    """
  end

  def action(:increment, _params, state) do
    put(state, :count, state.count + 1)
  end
end
