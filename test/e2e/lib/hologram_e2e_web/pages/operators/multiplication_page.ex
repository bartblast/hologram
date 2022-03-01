defmodule HologramE2E.Operators.MultiplicationPage do
  use Hologram.Page

  route "/e2e/operators/multiplication"

  def init do
    %{
      left: 2,
      right: 3,
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
    Map.put(state, :result, state.left * state.right)
  end
end
