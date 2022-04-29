defmodule HologramE2E.ControlFlow.CaseExpressionPage do
  use Hologram.Page

  route "/e2e/control-flow/case-expression"

  def init(_params, _conn) do
    %{
      condition: 2,
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
    result =
      case state.condition do
        1 ->
          11

        2 ->
          22
      end

    Map.put(state, :result, result)
  end
end
