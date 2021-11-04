defmodule Hologram.E2E.Component3 do
  use Hologram.Component

  def init do
    %{
      text: "",
      value: :c3
    }
  end

  def template do
    ~H"""
    <div id="text-component-3">{@text}</div>
    """
  end

  def action(:component_3_action_1, _params, state) do
    update(state, :text, "text updated by component_3_action_1, state.value = #{state.value}")
  end

  def action(:component_3_action_2, params, state) do
    update(
      state,
      :text,
      "text updated by component_3_action_2, params.a = #{params.a}, params.b = #{params.b}, state.value = #{state.value}"
    )
  end

  def action(:component_3_action_3, _params, state) do
    update(state, :text, "text updated by component_3_action_3, state.value = #{state.value}")
  end

  def command(:component_3_command_1, _params) do
    {:page, :action_7_b}
  end

  def command(:component_3_command_2, params) do
    {:page, :action_8_b, a: params.a * 10, b: params.b * 10}
  end
end
