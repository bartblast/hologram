defmodule HologramFeatureTests.Patching.Page5 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/5"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component, :text, "initial text")
  end

  def template do
    ~HOLO"""
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Runtime />
        <CommonLayoutStyles />
      </head>
      <body>
        <p>
          <form>
            <label for="text_input">Text Input:</label>
            <input type="text" id="text_input" value={@text} />
            <br /><br />
          </form>
        </p>
        
        <div>
          <button $click="update_text_1">Update Text 1</button>
          <button $click="update_text_2">Update Text 2</button>
          <button $click="clear_state">Clear State</button>
        </div>
      </body>
    </html>
    """
  end

  def action(:update_text_1, _params, component) do
    put_state(component, :text, "updated text 1")
  end

  def action(:update_text_2, _params, component) do
    put_state(component, :text, "updated text 2")
  end

  def action(:clear_state, _params, component) do
    put_state(component, :text, "")
  end
end
