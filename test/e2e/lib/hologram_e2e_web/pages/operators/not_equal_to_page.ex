defmodule HologramE2E.Operators.NotEqualToPage do
  use Hologram.Page

  route "/e2e/operators/not-equal-to"

  def init(_params, _conn) do
    %{
      left: 1,
      right: 2,
      result: 0
    }
  end

  def template do
    ~H"""
    <button id="button" on:click="calculate">Calculate</button>
    <div id="text">Result = {@result}</div>
    """
  end

  def action(:calculate, _params, state) do
    Map.put(state, :result, state.left != state.right)
  end
end
