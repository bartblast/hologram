defmodule HologramFeatureTests.Events.Change.Page1 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/change/1"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      result: nil,
      checkbox: true,
      email: "initial email",
      multiple_select: ["option_2", "option_3"],
      radio: "option_2",
      single_select: "option_2",
      text: "initial text",
      textarea: "initial textarea"
    )
  end

  def template do
    ~HOLO"""
    <p>
      <form>
        <input $change="handle_text_input_change" type="text" id="text_input_elem" value={@text} />
        <br /><br />
        
        <input $change="handle_email_input_change" type="email" id="email_input_elem" value={@email} />
        <br /><br />
        
        <textarea $change="handle_textarea_change" id="textarea_elem" value={@textarea} />
        <br /><br />
        
        <input $change="handle_checkbox_change" type="checkbox" id="checkbox_elem" checked={@checkbox} />
        <label for="checkbox_elem">Checkbox</label>
        <br /><br />

        <input $change="handle_radio_change" type="radio" name="radio_group" id="radio_elem_1" value="option_1" checked={@radio == "option_1"} />
        <label for="radio_elem_1">Radio Option 1</label>
        <br />
        <input type="radio" name="radio_group" id="radio_elem_2" value="option_2" checked={@radio == "option_2"} />
        <label for="radio_elem_2">Radio Option 2</label>
        <br /><br />

        <select $change="handle_single_select_change" id="single_select_elem">
          <option value="option_1" selected={@single_select == "option_1"}>Option 1</option>
          <option value="option_2" selected={@single_select == "option_2"}>Option 2</option>
          <option value="option_3" selected={@single_select == "option_3"}>Option 3</option>
        </select>
        <br /><br />
        
        <select $change="handle_multiple_select_change" id="multiple_select_elem" multiple>
          <option value="option_1" selected={"option_1" in @multiple_select}>Option 1</option>
          <option value="option_2" selected={"option_2" in @multiple_select}>Option 2</option>
          <option value="option_3" selected={"option_3" in @multiple_select}>Option 3</option>
          <option value="option_4" selected={"option_4" in @multiple_select}>Option 4</option>
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
    component
    |> put_state(:checkbox, params.event.value)
    |> put_state(:result, {:checkbox, params})
  end

  def action(:handle_email_input_change, params, component) do
    component
    |> put_state(:email, params.event.value)
    |> put_state(:result, {:email_input, params})
  end

  def action(:handle_multiple_select_change, params, component) do
    component
    |> put_state(:multiple_select, params.event.value)
    |> put_state(:result, {:multiple_select, params})
  end

  def action(:handle_radio_change, params, component) do
    component
    |> put_state(:radio, params.event.value)
    |> put_state(:result, {:radio, params})
  end

  def action(:handle_single_select_change, params, component) do
    component
    |> put_state(:single_select, params.event.value)
    |> put_state(:result, {:single_select, params})
  end

  def action(:handle_text_input_change, params, component) do
    component
    |> put_state(:text, params.event.value)
    |> put_state(:result, {:text_input, params})
  end

  def action(:handle_textarea_change, params, component) do
    component
    |> put_state(:textarea, params.event.value)
    |> put_state(:result, {:textarea, params})
  end
end
