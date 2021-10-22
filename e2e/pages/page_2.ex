defmodule Hologram.E2E.Page2 do
  use Hologram.Page

  route "/e2e/page-2"

  def state do
    %{
      text: ""
    }
  end

  def template do
    ~H"""
    <h1>Page 2</h1>

    <button id="page-2-update-text-button" on_click="update_text">Update text</button>
    <button id="page-2-back-button">Back</button>
    <br />

    <div id="page-2-text">{@text}</div><br />

    <script>
      document.getElementById("page-2-back-button")
        .addEventListener("click", () => &lcub; history.back() &rcub;)
    </script>
    """
  end

  def action(:update_text, _params, state) do
    update(state, :text, "text updated by page 2 update button")
  end
end
