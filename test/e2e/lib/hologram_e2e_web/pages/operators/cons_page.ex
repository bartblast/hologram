defmodule HologramE2E.Operators.ConsPage do
  use Hologram.Page

  route "/e2e/operators/cons"

  def init(_params, _conn) do
    %{
      head: 1,
      tail: [2, 3],
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
    Map.put(state, :result, [state.head | state.tail])
  end
end
