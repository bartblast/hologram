defmodule HologramE2E.Runtime.ActionsPage do
  use Hologram.Page
  alias HologramE2E.Component3, warn: false

  route "/e2e/runtime/actions"

  def init(_params, _conn) do
    %{
      text: "",
      value: :p1,
      x: 0
    }
  end

  def template do
    ~H"""
    <button id="button-6" on:click="action_4">Action 4</button>
    <button id="button-7" on:click="action_5">Action 5</button>
    <button id="button-8" on:click="action_6">Action 6</button>
    <button id="button-9" on:click="action_7">Action 7</button>
    <button id="button-10" on:click="action_8">Action 8</button>
    <button id="button-11" on:click="action_9">Action 9</button>
    <button id="button-13" on:click={:component_3_id, :component_3_action_3}>Component 3 Action 3</button>
    <br />

    <div id="text">{@text}</div><br />

    <Component3 id="component_3_id" /><br />
    """
  end

  def action(:action_4, _params, state) do
    {put(state, :text, "text updated by action_4, state.value = #{state.value}")}
  end

  def action(:action_5, _params, state) do
    {state, :command_1}
  end

  def action(:action_5_b, _params, state) do
    put(
      state,
      :text,
      "text updated by action_5_b triggered by command_1, state.value = #{state.value}"
    )
  end

  def action(:action_6, _params, state) do
    {state, :command_2, a: 1, b: 2}
  end

  def action(:action_6_b, params, state) do
    put(
      state,
      :text,
      "text updated by action_6_b triggered by command_2, params.a = #{params.a}, params.b = #{params.b}, state.value = #{state.value}"
    )
  end

  def action(:action_7, _params, state) do
    {state, :component_3_id, :component_3_command_1}
  end

  def action(:action_7_b, _params, state) do
    put(
      state,
      :text,
      "text updated by action_7_b triggered by component_3_command_1, state.value = #{state.value}"
    )
  end

  def action(:action_8, _params, state) do
    {state, :component_3_id, :component_3_command_2, a: 1, b: 2}
  end

  def action(:action_8_b, params, state) do
    put(
      state,
      :text,
      "text updated by action_8_b triggered by component_3_command_2, params.a = #{params.a}, params.b = #{params.b}, state.value = #{state.value}"
    )
  end

  def action(:action_9, _params, state) do
    put(state, :text, "text updated by action_9, state.value = #{state.value}")
  end

  def action(:action_13_b, _params, state) do
    put(state, :text, "text updated by action_13_b, state.value = #{state.value}")
  end

  def command(:command_1, _params) do
    :action_5_b
  end

  def command(:command_2, params) do
    {:action_6_b, a: params.a * 10, b: params.b * 10}
  end

  def command(:command_3, _params) do
    :action_13_b
  end
end
