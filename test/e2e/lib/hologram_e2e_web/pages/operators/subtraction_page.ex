defmodule Hologram.E2E.Operators.SubtractionPage do
  use Hologram.Page

  route "/e2e/operators/subtraction"

  def init do
    %{
      left: 10,
      right: 6,
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
    Map.put(state, :result, state.left - state.right)
  end
end
