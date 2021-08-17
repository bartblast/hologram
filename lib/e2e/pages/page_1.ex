defmodule Hologram.E2E.Page1 do
  use Hologram.Page

  route "/e2e/page-1"

  def state do
    %{
      text: ""
    }
  end

  def template do
    ~H"""
    <body>
      <h1>Page 1</h1>
      <button id="page-1-action-1-button" on_click="action_1">Action 1</button>
      <button id="page-1-action-2-button" on_click={:action_2, a: 5, b: 6}>Action 2</button>
      <button id="page-1-command-3-button" on_click.command="command_3">Command 3</button>
      <button id="page-1-command-4-button" on_click.command="command_4">Command 4</button>
      <button id="page-1-command-5-button" on_click.command="command_5">Command 5</button>
      <button id="page-1-command-6-button" on_click.command={:command_6, a: 1, b: 2}>Command 6</button>
      <button id="page-1-action-7-button" on_click="action_7">Action 7</button>
      <button id="page-1-action-8-button" on_click="action_8">Action 8</button>
      <button id="page-1-forward-button">Forward</button>
      <div id="text">{@text}</div>
      <a id="page-2-link" href={Hologram.E2E.Page2.route()} on_click.command={:__redirect__, page: Hologram.E2E.Page2}>Page 2</a>
      <script>
        document.getElementById("page-1-forward-button")
          .addEventListener("click", () => &lcub; history.forward() &rcub;)
      </script>
    </body>
    """
  end

  def action(:action_1, _params, state) do
    update(state, :text, "text updated by action_1")
  end

  def action(:action_2, params, state) do
    update(state, :text, "text updated by action_2_#{params.a}_#{params.b}")
  end

  def action(:action_3a, _params, state) do
    update(state, :text, "text updated by action_3a")
  end

  def action(:action_4a, params, state) do
    update(state, :text, "text updated by action_4a_#{params.a}_#{params.b}")
  end

  def action(:action_5a, _params, state) do
    update(state, :text, "text updated by action_5a")
  end

  def action(:action_6a_1_2, _params, state) do
    update(state, :text, "text updated by action_6a_1_2")
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

  def command(:command_5, _params) do
    :action_5a
  end

  def command(:command_6, params) do
    :"action_6a_#{params.a}_#{params.b}"
  end

  def command(:command_7, _params) do
    :action_7a
  end

  def command(:command_8, params) do
    :"action_8a_#{params.a}_#{params.b}"
  end
end
