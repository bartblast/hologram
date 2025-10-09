defmodule HologramFeatureTests.Events.SubmitPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/submit"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <form $submit="handle_form_submit">
        <input type="text" name="empty_text" />
        <br /><br />
        
        <!-- This will be filled programmatically in test -->
        <input type="text" name="non_empty_text" />
        <br /><br />        
        
        <input type="email" name="empty_email" />
        <br /><br />
        
        <input type="email" name="non_empty_email" value="my_email@test.com" />
        <br /><br />        
        
        <textarea name="empty_textarea" />
        <br /><br />
        
        <textarea name="non_empty_textarea" value="my_textarea" />
        <br /><br />  
        
        <input type="checkbox" name="checked_checkbox" checked />
        <input type="checkbox" name="non_checked_checkbox" />
        <br /><br />
        
        <input type="radio" name="radio_group" value="option_1" />
        <input type="radio" name="radio_group" value="option_2" checked />
        <input type="radio" name="radio_group" value="option_3" />        
        <br /><br />

        <select name="single_select">
          <option value="option_1">Option 1</option>
          <option value="option_2">Option 2</option>
          <option value="option_3" selected>Option 3</option>
        </select>
        <br /><br />
        
        <button type="submit">Submit</button>
      </form>
    </p>

    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:handle_form_submit, params, component) do
    put_state(component, :result, {:form, params})
  end
end
