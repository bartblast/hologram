defmodule Hologram.E2E.Page13 do
  use Hologram.Page

  route "/e2e/page-13"

  def init do
    %{
      count: 0
    }
  end

  def template do
    ~H"""
    <button id="target" on:pointer_up="increment_count">Target</button>
    <div id="text">Event count: {@count}</div>
    """
  end

  def action(:increment_count, _params, state) do
    Map.put(state, :count, state.count + 1)
  end
end
