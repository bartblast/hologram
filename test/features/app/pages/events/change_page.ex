defmodule HologramFeatureTests.Events.ChangePage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/change"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <form>
        <input $change="handle_text_input_change" type="text" id="text_input_elem" value="initial text" />
        <br /><br />
        
        <input $change="handle_email_input_change" type="email" id="email_input_elem" value="initial email" />
        <br /><br />
        
        <textarea $change="handle_textarea_change" id="textarea_elem">initial textarea</textarea>
        <br /><br />
        
        <input $change="handle_checkbox_change" type="checkbox" id="checkbox_elem" checked />
        <label for="checkbox_elem">Checkbox</label>
        <br /><br />
        
        <input $change="handle_radio_change" type="radio" name="radio_group" id="radio_elem_1" value="option_1" />
        <label for="radio_elem_1">Radio Option 1</label>
        <br />
        <input type="radio" name="radio_group" id="radio_elem_2" value="option_2" checked />
        <label for="radio_elem_2">Radio Option 2</label>
        <br /><br />

        <select $change="handle_single_select_change" id="single_select_elem">
          <option value="option_1">Option 1</option>
          <option value="option_2" selected>Option 2</option>
          <option value="option_3">Option 3</option>
        </select>
        <br /><br />
        
        <select $change="handle_multiple_select_change" id="multiple_select_elem" multiple>
          <option value="option_1">Option 1</option>
          <option value="option_2" selected>Option 2</option>
          <option value="option_3" selected>Option 3</option>
          <option value="option_4">Option 4</option>
        </select>
      </form>
    </p>

    <p>
      <button>Blur</button>
    </p>

    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:handle_checkbox_change, params, component) do
    put_state(component, :result, {"checkbox", params})
  end

  def action(:handle_email_input_change, params, component) do
    put_state(component, :result, {"email input", params})
  end

  def action(:handle_multiple_select_change, params, component) do
    put_state(component, :result, {"multiple select", params})
  end

  def action(:handle_radio_change, params, component) do
    put_state(component, :result, {"radio", params})
  end

  def action(:handle_single_select_change, params, component) do
    put_state(component, :result, {"single select", params})
  end

  def action(:handle_text_input_change, params, component) do
    put_state(component, :result, {"text input", params})
  end

  def action(:handle_textarea_change, params, component) do
    put_state(component, :result, {"textarea", params})
  end
end
