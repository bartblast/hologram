defmodule HologramE2E.Operators.UnaryNegativePage do
  use Hologram.Page

  route "/e2e/operators/unary-negative"

  def init(_params, _conn) do
    %{
      value: 123,
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
    Map.put(state, :result, -state.value)
  end
end
