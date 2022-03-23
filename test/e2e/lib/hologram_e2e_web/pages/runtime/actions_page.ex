defmodule HologramE2E.Runtime.ActionsPage do
  use Hologram.Page
  alias HologramE2E.Component3, warn: false

  route "/e2e/runtime/actions"

  def init do
    %{
      text: "",
      value: :p1,
      x: 0
    }
  end

  def template do
    ~H"""
    <button id="button-1" on:click="action_1">Action 1</button>
    <button id="button-2" on:click={:action_2}>Action 2</button>
    <button id="button-3" on:click={:action_3, a: 5, b: 6}>Action 3</button>
    <button id="button-4" on:click={:component_3_id, :component_3_action_1}>Component 3 Action 1</button>
    <button id="button-5" on:click={:component_3_id, :component_3_action_2, a: 5, b: 6}>Component 3 Action 2</button>
    <button id="button-6" on:click="action_4">Action 4</button>
    <button id="button-7" on:click="action_5">Action 5</button>
    <button id="button-8" on:click="action_6">Action 6</button>
    <button id="button-9" on:click="action_7">Action 7</button>
    <button id="button-10" on:click="action_8">Action 8</button>
    <button id="button-11" on:click="action_9">Action 9</button>
    <button id="button-12" on:click="action_10">Action 10</button>
    <button id="button-13" on:click={:component_3_id, :component_3_action_3}>Component 3 Action 3</button>
    <button id="button-14" on:click={:page, :action_11}>Action 11</button>
    <button id="button-15" on:click={:layout, :default_layout_action_1}>Layout Action 1</button>
    <button id="button-16" on:click="action_12">Action 12</button>
    <button id="button-17" on:click="action_13">Action 13</button>
    <br />

    <div id="text">{@text}</div><br />

    <Component3 id="component_3_id" /><br />
    """
  end

  def action(:action_1, _params, state) do
    put(state, :text, "text updated by action_1, state.value = #{state.value}")
  end

  def action(:action_2, _params, state) do
    put(state, :text, "text updated by action_2, state.value = #{state.value}")
  end

  def action(:action_3, params, state) do
    put(
      state,
      :text,
      "text updated by action_3, params.a = #{params.a}, params.b = #{params.b}, state.value = #{state.value}"
    )
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

  def action(:action_10, _params, state) do
    put(state, :text, "text updated by action_10, state.value = #{state.value}")
  end

  def action(:action_11, _params, state) do
    put(state, :text, "text updated by action_11, state.value = #{state.value}")
  end

  def action(:action_12, _params, state) do
    put(state, :text, "text updated by action_12, state.value = #{state.value}")
  end

  def action(:action_13, _params, state) do
    {state, :command_3}
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
