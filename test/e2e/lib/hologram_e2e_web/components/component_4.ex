defmodule Hologram.E2E.Component4 do
  use Hologram.Component

  def init do
    %{
      text: "",
      value: :c4
    }
  end

  def template do
    ~H"""
    <div id="text-component-4">{@text}</div><br />

    <button id="component-4-button-1" on:click.command={:page, :command_10}>Page 4 Command 10</button>
    """
  end

  def action(:component_4_action_1_b, _params, state) do
    put(state, :text, "text updated by component_4_action_1_b, state.value = #{state.value}")
  end

  def action(:component_4_action_2_b, params, state) do
    put(
      state,
      :text,
      "text updated by component_4_action_2_b, params.a = #{params.a}, params.b = #{params.b}, state.value = #{state.value}"
    )
  end

  def action(:component_4_action_3_b, _params, state) do
    put(state, :text, "text updated by component_4_action_3_b, state.value = #{state.value}")
  end

  def action(:component_4_action_4_b, params, state) do
    put(
      state,
      :text,
      "text updated by component_4_action_4_b, params.a = #{params.a}, params.b = #{params.b}, state.value = #{state.value}"
    )
  end

  def action(:component_4_action_5_b, _params, state) do
    put(state, :text, "text updated by component_4_action_5_b, state.value = #{state.value}")
  end

  def command(:component_4_command_1, _params) do
    :component_4_action_1_b
  end

  def command(:component_4_command_2, params) do
    {:component_4_action_2_b, a: params.a * 10, b: params.b * 10}
  end

  def command(:component_4_command_3, _params) do
    :component_4_action_5_b
  end
end
