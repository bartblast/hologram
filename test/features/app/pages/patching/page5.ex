defmodule HologramFeatureTests.Patching.Page5 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/5"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component, email: "initial email", text: "initial text")
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
            <button type="button" $click="clear_state">Clear State</button>
            <br /><br />

            <label for="text_input">Text Input:</label>
            <input type="text" id="text_input" value={@text} />
            <button type="button" $click="update_text_1">Update Text 1</button>
            <button type="button" $click="update_text_2">Update Text 2</button>            
            <br /><br />
            
            <label for="email_input">Email Input:</label>
            <input type="email" id="email_input" value={@email} />
            <button type="button" $click="update_email_1">Update Email 1</button>
            <button type="button" $click="update_email_2">Update Email 2</button>            
            <br /><br />            
          </form>
        </p>
      </body>
    </html>
    """
  end

  def action(:update_email_1, _params, component) do
    put_state(component, :email, "updated email 1")
  end

  def action(:update_email_2, _params, component) do
    put_state(component, :email, "updated email 2")
  end

  def action(:update_text_1, _params, component) do
    put_state(component, :text, "programmatic 1")
  end

  def action(:update_text_2, _params, component) do
    put_state(component, :text, "programmatic 2")
  end

  def action(:clear_state, _params, component) do
    put_state(component, email: "", text: "")
  end
end
