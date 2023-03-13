defmodule HologramE2E.Types.AnonymousFunctionPage do
  use Hologram.Page

  route "/e2e/types/anonymous-function"

  def init(_params, _conn) do
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
    test_fun = fn x -> x * x end
    result = is_function(test_fun)

    Map.put(state, :result, result)
  end
end
