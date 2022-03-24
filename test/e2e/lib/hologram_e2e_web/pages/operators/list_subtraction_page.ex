defmodule HologramE2E.Operators.ListConcatenationPage do
  use Hologram.Page

  route "/e2e/operators/list-subtraction"

  def init do
    %{
      left: [1, 2, 3, 1, 2, 3, 1],
      right: [1, 3, 3, 4],
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
    Map.put(state, :result, state.left -- state.right)
  end
end
