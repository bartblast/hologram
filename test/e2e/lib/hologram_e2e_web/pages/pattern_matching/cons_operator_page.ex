defmodule HologramE2E.PatternMatching.ConsOperatorPage do
  use Hologram.Page

  route "/e2e/pattern-matching/cons-operator"

  def init do
    %{
      case_condition_value: [3 | [4, 5]],
      function_call_value: [2 | [3, 4]],
      match_expression_value: [1 | [2, 3]],
      result: 0
    }
  end

  def template do
    ~H"""
    <button id="button_match_expression" on:click="test_match_expression">Test match expression</button>
    <button id="button_function_call" on:click="test_function_call">Test function call</button>
    <button id="button_case_condition" on:click="test_case_condition">Test case condition</button>
    <div id="text">Result = {@result}</div>
    """
  end

  def action(:test_match_expression, _params, state) do
    [h | t] = state.match_expression_value
    Map.put(state, :result, h + Enum.count(t))
  end

  def action(:test_function_call, _params, state) do
    result = dummy_function(state.function_call_value)
    Map.put(state, :result, result)
  end

  def action(:test_case_condition, _params, state) do
    result =
      case state.case_condition_value do
        123 ->
          :not_matched

        [h | t] ->
          h + Enum.count(t)

        _ ->
          :default_match
      end

    Map.put(state, :result, result)
  end

  defp dummy_function([h | t]) do
    h + Enum.count(t)
  end
end
