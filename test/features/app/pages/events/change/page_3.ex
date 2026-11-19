defmodule HologramFeatureTests.Events.Change.Page3 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/change/3"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  # A form control's name becomes a property of the form that hides the form's own property of
  # that name, so these names hide the properties a change handler could use to tell a form from
  # a field (localName) and to look the form's fields up (elements).
  def template do
    ~HOLO"""
    <p>
      <form $change="handle_form_change">
        <input type="text" name="localName" />
        <br /><br />

        <input type="checkbox" name="elements" checked />
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

  def action(:handle_form_change, params, component) do
    put_state(component, :result, {:form, params})
  end
end
