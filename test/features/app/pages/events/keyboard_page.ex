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
      <input $key_up="handle_key_up" id="my_input_key_up" type="text" />
    </p>
    <p>
      <input $key_down.enter="handle_enter" id="my_input_enter" type="text" />
    </p>
    <p>
      <input $key_down.ctrl+k="handle_ctrl_k" id="my_input_ctrl_k" type="text" />
    </p>
    <p>
      <input $key_down.arrow_up="handle_key_down_arrow_up" id="my_input_key_down_arrow_up" type="text" />
    </p>
    <p>
      <input $key_up.arrow_up="handle_key_up_arrow_up" id="my_input_key_up_arrow_up" type="text" />
    </p>
    <p>
      <input $key_down.slash="handle_slash" id="my_input_slash" type="text" />
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:handle_ctrl_k, params, component) do
    put_state(component, :result, {:ctrl_k, params})
  end

  def action(:handle_enter, params, component) do
    put_state(component, :result, {:enter, params})
  end

  def action(:handle_key_down, params, component) do
    put_state(component, :result, {:key_down, params})
  end

  def action(:handle_key_down_arrow_up, params, component) do
    put_state(component, :result, {:key_down_arrow_up, params})
  end

  def action(:handle_key_up, params, component) do
    put_state(component, :result, {:key_up, params})
  end

  def action(:handle_key_up_arrow_up, params, component) do
    put_state(component, :result, {:key_up_arrow_up, params})
  end

  def action(:handle_slash, params, component) do
    put_state(component, :result, {:slash, params})
  end
end
