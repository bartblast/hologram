defmodule Hologram.E2E.Page11 do
  use Hologram.Page

  route "/e2e/page-11"

  def init do
    %{
      text: "Field has not been blurred",
    }
  end

  def template do
    ~H"""
    <h1>Page 11</h1>
    <form>
      <input id="input" type="text" name="field" on_blur="update" />
    </form>
    <div id="text">{@text}</div>
    """
  end

  def action(:update, _params, state) do
    update(state, :text, "Field has been blurred")
  end
end
