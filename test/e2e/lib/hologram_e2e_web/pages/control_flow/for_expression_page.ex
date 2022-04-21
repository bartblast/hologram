defmodule HologramE2E.ControlFlow.ForExpressionPage do
  use Hologram.Page

  route "/e2e/control-flow/for-expression"

  def init do
    %{
      result: 0
    }
  end

  def template do
    ~H"""
    <button id="button_non_nested" on:click="test_non_nested">Test non nested for expression</button>
    <div id="text">Result = {@result}</div>
    """
  end

  def action(:test_non_nested, _params, state) do
    result = for n <- [1, 2, 3], do: n * n
    Map.put(state, :result, result)
  end
end
