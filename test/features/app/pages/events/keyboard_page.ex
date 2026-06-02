defmodule HologramFeatureTests.Events.KeyboardPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/keyboard"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <input $key_down="handle_key_down" id="my_input_key_down" type="text" />
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:handle_key_down, params, component) do
    put_state(component, :result, params)
  end
end
