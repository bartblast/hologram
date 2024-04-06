defmodule HologramFeatureTests.OperatorsPage do
  use Hologram.Page
  
  route "/operators"
  
  layout HologramFeatureTests.Components.DefaultLayout
  
  def init(_params, component, _server) do
    put_state(component, boolean_a: true, boolean_b: false, integer_a: 123, integer_b: 234, list_a: [1, 2, 3], list_b: [2, 3, 4], result: nil)
  end
  
  def template do
    ~H"""
    <p>
      <button id="unary+" $click={:"unary+", value: @integer_a}> unary + </button>
      <button id="unary-" $click={:"unary-", value: @integer_a}> unary - </button>
      <button id="+" $click={:+, left: @integer_a, right: @integer_b}> + </button>
      <button id="-" $click={:-, left: @integer_a, right: @integer_b}> - </button>
      <button id="*" $click={:*, left: @integer_a, right: @integer_b}> * </button>
      <button id="/" $click={:/, left: @integer_a, right: @integer_b}> / </button>
      <button id="++" $click={:++, left: @list_a, right: @list_b}> ++ </button>
      <button id="--" $click={:--, left: @list_a, right: @list_b}> -- </button>
      <button id="and" $click={:and, left: @boolean_a, right: @boolean_b}> and </button>
    </p>
    <p>
      Result: <strong id="result">{inspect(@result)}</strong>
    </p>
    """
  end
  
  def action(:"unary+", %{value: value}, component) do
    put_state(component, :result, +value)
  end
  
  def action(:"unary-", %{value: value}, component) do
    put_state(component, :result, -value)
  end
  
  def action(:+, %{left: left, right: right}, component) do
    put_state(component, :result, left + right)
  end
  
  def action(:-, %{left: left, right: right}, component) do
    put_state(component, :result, left - right)
  end
  
  def action(:*, %{left: left, right: right}, component) do
    put_state(component, :result, left * right)
  end
  
  def action(:/, %{left: left, right: right}, component) do
    put_state(component, :result, left / right)
  end
  
  def action(:++, %{left: left, right: right}, component) do
    put_state(component, :result, left ++ right)
  end
  
  def action(:--, %{left: left, right: right}, component) do
    put_state(component, :result, left -- right)
  end
  
  def action(:and, %{left: left, right: right}, component) do
    put_state(component, :result, left and right)
  end
end
