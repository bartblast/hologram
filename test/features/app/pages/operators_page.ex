defmodule HologramFeatureTests.OperatorsPage do
  use Hologram.Page

  route "/operators"

  layout HologramFeatureTests.Components.DefaultLayout

  @integer_c 345

  def init(_params, component, _server) do
    put_state(component,
      boolean_a: true,
      boolean_b: false,
      integer_a: 123,
      integer_b: 234,
      integer_c: @integer_c,
      list_a: [1, 2, 3],
      list_b: [2, 3, 4],
      result: nil
    )
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
      <button id="&amp;&amp;" $click={:&&, left: @boolean_a, right: @boolean_b}> &amp;&amp; </button>
      <button id="or" $click={:or, left: @boolean_a, right: @boolean_b}> or </button>
      <button id="||" $click={:||, left: @boolean_a, right: @boolean_b}> || </button>
      <button id="not" $click={:not, value: @boolean_a}> not </button>
      <button id="!" $click={:!, value: @boolean_a}> ! </button>
      <button id="in" $click={:in, left: @integer_a, right: @list_a}> in </button>
      <button id="not in" $click={:"not in", left: @integer_a, right: @list_a}> not in </button>
      <button id="@" $click="@"> @ </button>
      <button id=".." $click={:.., left: @integer_a, right: @integer_b}> .. </button>
      <button id="..//" $click={:..//, first: @integer_a, last: @integer_b, step: @integer_c}> ..// </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
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

  def action(:&&, %{left: left, right: right}, component) do
    put_state(component, :result, left && right)
  end

  def action(:or, %{left: left, right: right}, component) do
    put_state(component, :result, left or right)
  end

  def action(:||, %{left: left, right: right}, component) do
    put_state(component, :result, left || right)
  end

  def action(:not, %{value: value}, component) do
    put_state(component, :result, not value)
  end

  def action(:!, %{value: value}, component) do
    put_state(component, :result, !value)
  end

  def action(:in, %{left: left, right: right}, component) do
    put_state(component, :result, left in right)
  end

  def action(:"not in", %{left: left, right: right}, component) do
    put_state(component, :result, left not in right)
  end

  def action(:@, _params, component) do
    put_state(component, :result, @integer_c)
  end

  def action(:.., %{left: left, right: right}, component) do
    put_state(component, :result, left..right)
  end

  def action(:"..//", %{first: first, last: last, step: step}, component) do
    put_state(component, :result, first..last//step)
  end
end
