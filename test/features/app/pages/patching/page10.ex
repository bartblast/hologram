defmodule HologramFeatureTests.Patching.Page10 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/10"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component,
      email: "initial email",
      text: "initial text",
      textarea: "initial textarea"
    )
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
            <button type="button" $click="clear_all_state">Clear All State</button>
            <br /><br />

            <label for="text_input">Text Input:</label>
            <input type="text" id="text_input" value={@text} $change="change_text" />
            <button type="button" $click="update_text_1">Update Text 1</button>
            <button type="button" $click="update_text_2">Update Text 2</button>
            <div id="text_result">{@text}</div>         
            <br /><br />
            
            <label for="email_input">Email Input:</label>
            <input type="email" id="email_input" value={@email} $change="change_email" />
            <button type="button" $click="update_email_1">Update Email 1</button>
            <button type="button" $click="update_email_2">Update Email 2</button>       
            <div id="email_result">{@email}</div>      
            <br /><br />  
            
            <label for="textarea">Textarea:</label>
            <textarea id="textarea" value={@textarea} $change="change_textarea" />
            <button type="button" $click="update_textarea_1">Update Textarea 1</button>
            <button type="button" $click="update_textarea_2">Update Textarea 2</button>  
            <div id="textarea_result">{@textarea}</div>           
            <br /><br />        
          </form>
        </p>
      </body>
    </html>
    """
  end

  def action(:change_email, params, component) do
    put_state(component, :email, params.event.value)
  end

  def action(:update_email_1, _params, component) do
    put_state(component, :email, "programmatic 1")
  end

  def action(:update_email_2, _params, component) do
    put_state(component, :email, "programmatic 2")
  end

  def action(:change_text, params, component) do
    put_state(component, :text, params.event.value)
  end

  def action(:update_text_1, _params, component) do
    put_state(component, :text, "programmatic 1")
  end

  def action(:update_text_2, _params, component) do
    put_state(component, :text, "programmatic 2")
  end

  def action(:change_textarea, params, component) do
    put_state(component, :textarea, params.event.value)
  end

  def action(:update_textarea_1, _params, component) do
    put_state(component, :textarea, "programmatic 1")
  end

  def action(:update_textarea_2, _params, component) do
    put_state(component, :textarea, "programmatic 2")
  end

  def action(:clear_all_state, _params, component) do
    put_state(component,
      email: "",
      text: "",
      textarea: ""
    )
  end
end
