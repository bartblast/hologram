defmodule Hologram.E2E.Page2 do
  use Hologram.Page

  route "/e2e/page-2"

  def state() do
    %{
      text: ""
    }
  end

  def template do
    ~H"""
    <body>
      <h1>Page 2</h1>
      <button id="button" on_click="update_text">Update text</button>
      <div id="text">{{ @text }}</div>
    </body>
    """
  end

  def action(:update_text, _params, state) do
    update(state, :text, "test updated text")
  end
end
