defmodule Hologram.E2E.Page5 do
  use Hologram.Page

  route "/e2e/page-5"

  def init do
    %{
      text: ""
    }
  end

  def template do
    ~H"""
    <h1>Page 5</h1>

    <button id="page-5-update-text-button" on:click="update_text">Update text</button>
    <button id="page-5-forward-button">Forward</button>
    <br />

    <div id="page-5-text">{@text}</div><br />

    <a id="page-2-link" href={Hologram.E2E.Page2.route()} on:click.command={:__redirect__, page: Hologram.E2E.Page2}>Page 2</a><br />

    <script>
      document.getElementById("page-5-forward-button")
        .addEventListener("click", () => \{ history.forward() \})
    </script>
    """
  end

  def action(:update_text, _params, state) do
    put(state, :text, "text updated by page 5 update button")
  end
end
