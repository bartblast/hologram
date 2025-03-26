defmodule HologramFeatureTests.Events.SelectPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/select"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <form>
        <input $select="selected_in_text_input" type="text" id="text_input_elem" value="Hologram 1 Hologram" />
        <br /><br >
        <textarea $select="selected_in_text_area" id="text_area_elem">Hologram 2 Hologram</textarea>
      </form>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:selected_in_text_input, params, component) do
    put_state(component, :result, {"text input", params})
  end

  def action(:selected_in_text_area, params, component) do
    put_state(component, :result, {"text area", params})
  end
end
