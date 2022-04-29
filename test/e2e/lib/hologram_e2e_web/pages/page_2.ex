defmodule HologramE2E.Page2 do
  use Hologram.Page

  route "/e2e/page-2"

  def init(_params, _conn) do
    %{
      text: ""
    }
  end

  def template do
    ~H"""
    <h1>Page 2</h1>

    <button id="page-2-update-text-button" on:click="update_text">Update text</button>
    <button id="page-2-back-button">Back</button>
    <br />

    <div id="page-2-text">{@text}</div><br />

    <script>
      document.getElementById("page-2-back-button")
        .addEventListener("click", () => \{ history.back() \})
    </script>
    """
  end

  def action(:update_text, _params, state) do
    put(state, :text, "text updated by page 2 update button")
  end
end
