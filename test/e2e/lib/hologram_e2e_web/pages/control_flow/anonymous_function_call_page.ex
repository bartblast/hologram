defmodule HologramE2E.ControlFlow.AnonymousFunctionCallPage do
  use Hologram.Page

  route "/e2e/control-flow/anonymous-function-call"

  def init do
    %{
      result: 0
    }
  end

  def template do
    ~H"""
    <button id="button_regular_syntax" on:click="test_regular_syntax">Test regular syntax</button>
    <div id="text">Result = {@result}</div>
    """
  end

  def action(:test_regular_syntax, _params, state) do
    test_fun = fn x, y -> x * y end
    result = test_fun.(2, 3)

    Map.put(state, :result, result)
  end
end
