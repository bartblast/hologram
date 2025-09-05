defmodule HologramFeatureTests.Patching.Page5 do
  use Hologram.Page

  alias Hologram.UI.Runtime
  alias HologramFeatureTests.Components.CommonLayoutStyles

  route "/patching/5"

  layout HologramFeatureTests.Components.EmptyLayout

  def init(_params, component, _server) do
    put_state(component,
      checkbox: true,
      email: "initial email",
      radio: "option_2",
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
            
            <label for="textarea">Textarea:</label>
            <textarea id="textarea" value={@textarea} />
            <button type="button" $click="update_textarea_1">Update Textarea 1</button>
            <button type="button" $click="update_textarea_2">Update Textarea 2</button>            
            <br /><br />
            
            <input type="checkbox" id="checkbox" checked={@checkbox} />
            <label for="checkbox">Checkbox</label>
            <button type="button" $click="check_checkbox">Check Checkbox</button>
            <button type="button" $click="uncheck_checkbox">Uncheck Checkbox</button>            
            <br /><br />
            
            <fieldset>
              <legend>Radio Buttons:</legend>
              <input type="radio" id="radio_option_1" name="radio_group" value="option_1" checked={@radio == "option_1"} />
              <label for="radio_option_1">Option 1</label><br />
              <input type="radio" id="radio_option_2" name="radio_group" value="option_2" checked={@radio == "option_2"} />
              <label for="radio_option_2">Option 2</label><br />
              <input type="radio" id="radio_option_3" name="radio_group" value="option_3" checked={@radio == "option_3"} />
              <label for="radio_option_3">Option 3</label><br />              
              <button type="button" $click={:select_radio, option: "option_1"}>Select Option 1</button>
              <button type="button" $click={:select_radio, option: "option_2"}>Select Option 2</button>
              <button type="button" $click={:select_radio, option: "option_3"}>Select Option 3</button>
            </fieldset>
          </form>
        </p>
      </body>
    </html>
    """
  end

  def action(:update_email_1, _params, component) do
    put_state(component, :email, "programmatic 1")
  end

  def action(:update_email_2, _params, component) do
    put_state(component, :email, "programmatic 2")
  end

  def action(:update_text_1, _params, component) do
    put_state(component, :text, "programmatic 1")
  end

  def action(:update_text_2, _params, component) do
    put_state(component, :text, "programmatic 2")
  end

  def action(:update_textarea_1, _params, component) do
    put_state(component, :textarea, "programmatic 1")
  end

  def action(:update_textarea_2, _params, component) do
    put_state(component, :textarea, "programmatic 2")
  end

  def action(:clear_state, _params, component) do
    put_state(component, checkbox: false, email: "", radio: "initial", text: "", textarea: "")
  end

  def action(:check_checkbox, _params, component) do
    put_state(component, :checkbox, true)
  end

  def action(:uncheck_checkbox, _params, component) do
    put_state(component, :checkbox, false)
  end

  def action(:select_radio, params, component) do
    put_state(component, :radio, params.option)
  end
end
