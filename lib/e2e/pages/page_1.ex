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
      <button id="button" on_click="button_clicked">Request async job</button>
      <div id="text">{@text}</div>
    </body>
    """
  end

  def action(:button_clicked, _params, state) do
    {state, :async_job}
  end

  def action(:update_text, _params, state) do
    update(state, :text, "test updated text")
  end

  def command(:async_job, _params) do
    :update_text
  end
end
