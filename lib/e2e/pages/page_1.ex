defmodule Hologram.E2E.Page1 do
  use Hologram.Page

  route "/e2e/page-1"

  def state() do
    %{
      text: ""
    }
  end

  def template do
    ~H"""
    <body>
      <h1>Page 1</h1>
      <button id="button_1" on_click="action_1">Action 1</button>
      <button id="button_2" on_click={:action_2, a: 5, b: 6}>Action 2</button>
      <button id="button_3" on_click="action_3">Action 3</button>
      <button id="button_4" on_click="action_4">Action 4</button>
      <button id="button_7" on_click="action_7">Action 7</button>
      <button id="button_8" on_click="action_8">Action 8</button>
      <div id="text">{@text}</div>
    </body>
    """
  end

  def action(:action_1, _params, state) do
    update(state, :text, "text updated by action_1")
  end

  def action(:action_2, params, state) do
    update(state, :text, "text updated by action_2_#{params.a}_#{params.b}")
  end

  def action(:action_3, _params, state) do
    # DEFER: instead of using action_3, trigger the command directly by an event
    {state, :command_3}
  end

  def action(:action_3a, _params, state) do
    update(state, :text, "text updated by action_3a")
  end

  def action(:action_4, _params, state) do
    # DEFER: instead of using action_4, trigger the command directly by an event
    {state, :command_4}
  end

  def action(:action_4a, params, state) do
    update(state, :text, "text updated by action_4a_#{params.a}_#{params.b}")
  end

  def action(:action_7, _params, state) do
    {state, :command_7}
  end

  def action(:action_7a, _params, state) do
    update(state, :text, "text updated by action_7a")
  end

  def action(:action_8, _params, state) do
    {state, :command_8, a: 5, b: 6}
  end

  def action(:action_8a_5_6, _params, state) do
    update(state, :text, "text updated by action_8a_5_6")
  end

  def command(:command_3, _params) do
    :action_3a
  end

  def command(:command_4, _params) do
    {:action_4a, a: 5, b: 6}
  end

  def command(:command_7, _params) do
    :action_7a
  end

  def command(:command_8, params) do
    :"action_8a_#{params.a}_#{params.b}"
  end
end
