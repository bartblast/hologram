defmodule HologramFeatureTests.Focus.Page1 do
  use Hologram.Page

  route "/focus/1"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, count: 0, focused_field: nil, sticky?: false)
  end

  # The email and password fields follow the state both ways: an action names the field, and
  # leaving it clears the name. The sticky field only takes focus from the state and never hands
  # it back, so a re-render that still declares it focused is what would steal focus if anything
  # did.
  def template do
    ~HOLO"""
    <p>
      <input type="text" id="page_1_email" $focused={@focused_field == :email} $blur="blurred" />
      <input type="text" id="page_1_password" $focused={@focused_field == :password} $blur="blurred" />
      <input type="text" id="page_1_sticky" $focused={@sticky?} />
      <input type="text" id="page_1_other" />
    </p>
    <p>
      <button id="page_1_focus_email" $click="focus_email">Focus email</button>
      <button id="page_1_focus_password" $click="focus_password">Focus password</button>
      <button id="page_1_focus_sticky" $click="focus_sticky">Focus sticky</button>
      <button id="page_1_increment" $click="increment">Increment</button>
      <button id="page_1_unfocus" $click="unfocus">Unfocus</button>
    </p>
    <p>Count: <strong id="page_1_count">{@count}</strong></p>
    """
  end

  def action(:blurred, _params, component) do
    put_state(component, :focused_field, nil)
  end

  def action(:focus_email, _params, component) do
    put_state(component, :focused_field, :email)
  end

  def action(:focus_password, _params, component) do
    put_state(component, :focused_field, :password)
  end

  def action(:focus_sticky, _params, component) do
    put_state(component, :sticky?, true)
  end

  def action(:increment, _params, component) do
    put_state(component, :count, component.state.count + 1)
  end

  def action(:unfocus, _params, component) do
    put_state(component, :focused_field, nil)
  end
end
