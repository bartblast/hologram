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
    <button id="button_single_generator" on:click="test_single_generator">
      Test for expression with single generator
    </button>
    <button id="button_multiple_generators" on:click="test_multiple_generators">
      Test for expression with multiple generators
    </button>
    <button id="button_nested" on:click="test_nested">
      Test nested for expressions
    </button>
    <button id="button_pattern_matching" on:click="test_pattern_matching">
      Test pattern matching
    </button>
    <div id="text">Result = {@result}</div>
    """
  end

  def action(:test_single_generator, _params, state) do
    result = for n <- [1, 2, 3], do: n * n
    Map.put(state, :result, result)
  end

  def action(:test_multiple_generators, _params, state) do
    result = for n <- [1, 2], m <- [3, 4], do: n * m
    Map.put(state, :result, result)
  end

  def action(:test_nested, _params, state) do
    result = for n <- [1, 2], do: [n] ++ for n <- [3, 4], do: n * n
    Map.put(state, :result, result)
  end

  def action(:test_pattern_matching, _params, state) do
    result = for {n, m} <- [{1, 2}, {3, 4}], do: n * m
    Map.put(state, :result, result)
  end
end
