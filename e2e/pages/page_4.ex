defmodule Hologram.E2E.Page4 do
  use Hologram.Page
  alias Hologram.E2E.Component4, warn: false

  route "/e2e/page-4"

  def state do
    %{
      text: "",
      value: :p4,
      x: 0
    }
  end

  def template do
    ~H"""
    <h1>Page 4</h1><br />

    <button id="page-4-button-1" on_click.command="command_1">Command 1</button>
    <button id="page-4-button-2" on_click.command={:command_2}>Command 2</button>
    <button id="page-4-button-3" on_click.command={:command_3, a: 5, b: 6}>Command 3</button>
    <button id="page-4-button-4" on_click.command={:component_4_id, :component_4_command_1}>Component 4 Command 1</button>
    <button id="page-4-button-5" on_click.command={:component_4_id, :component_4_command_2, a: 5, b: 6}>Component 4 Command 2</button>
    <button id="page-4-button-6" on_click.command="command_4">Command 4</button>
    <button id="page-4-button-7" on_click.command={:command_5}>Command 5</button>
    <button id="page-4-button-8" on_click.command={:command_6, a: 5, b: 6}>Command 6</button>
    <button id="page-4-button-9" on_click.command="command_7">Command 7</button>
    <button id="page-4-button-10" on_click.command={:command_8, a: 5, b: 6}>Command 8</button>
    <button id="page-4-button-11" on_click.command="command_9">Command 9</button>
    <button id="page-4-button-12" on_click.command={:component_4_id, :component_4_command_3}>Component 4 Command 3</button>
    <button id="page-4-button-13" on_click.command={:layout, :default_layout_command_1}>Layout 4 Command 1</button>
    <button id="page-4-button-14" on_click.command="command_11">Command 11</button>
    <button id="page-4-button-15" on_click="action_12">Action 12</button>
    <br />

    <div id="text-page-4">{@text}</div><br />

    <Component4 id="component_4_id" /><br />
    """
  end

  def action(:action_1_b, _params, state) do
    update(state, :text, "text updated by action_1_b, state.value = #{state.value}")
  end

  def action(:action_2_b, _params, state) do
    update(state, :text, "text updated by action_2_b, state.value = #{state.value}")
  end

  def action(:action_3_b, params, state) do
    update(state, :text, "text updated by action_3_b, params.a = #{params.a}, params.b = #{params.b}, state.value = #{state.value}")
  end

  def action(:action_4_b, _params, state) do
    update(state, :text, "text updated by action_4_b, state.value = #{state.value}")
  end

  def action(:action_5_b, _params, state) do
    update(state, :text, "text updated by action_5_b, state.value = #{state.value}")
  end

  def action(:action_6_b, params, state) do
    update(state, :text, "text updated by action_6_b, params.a = #{params.a}, params.b = #{params.b}, state.value = #{state.value}")
  end

  def action(:action_9_b, _params, state) do
    update(state, :text, "text updated by action_9_b, state.value = #{state.value}")
  end

  def action(:action_10_b, _params, state) do
    update(state, :text, "text updated by action_10_b, state.value = #{state.value}")
  end

  def action(:action_11_b, _params, state) do
    update(state, :text, "text updated by action_11_b, state.value = #{state.value}")
  end

  def action(:action_12, _params, state) do
    {state, :command_12}
  end

  def action(:action_12_b, _params, state) do
    update(state, :text, "text updated by action_12_b, state.value = #{state.value}")
  end

  def command(:command_1, _params) do
    :action_1_b
  end

  def command(:command_2, _params) do
    :action_2_b
  end

  def command(:command_3, params) do
    {:action_3_b, a: params.a * 10, b: params.b * 10}
  end

  def command(:command_4, _params) do
    :action_4_b
  end

  def command(:command_5, _params) do
    :action_5_b
  end

  def command(:command_6, params) do
    {:action_6_b, a: params.a * 10, b: params.b * 10}
  end

  def command(:command_7, _params) do
    {:component_4_id, :component_4_action_3_b}
  end

  def command(:command_8, params) do
    {:component_4_id, :component_4_action_4_b, a: params.a * 10, b: params.b * 10}
  end

  def command(:command_9, _params) do
    :action_9_b
  end

  def command(:command_10, _params) do
    :action_10_b
  end

  def command(:command_11, _params) do
    :action_11_b
  end

  def command(:command_12, _params) do
    :action_12_b
  end
end
