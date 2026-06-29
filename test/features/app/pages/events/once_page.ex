defmodule HologramFeatureTests.Events.OncePage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/events/once"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, click_count: 0)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click.once="record_click" id="click_button">Click</button>
    </p>
    <p>
      Click: <strong id="click_result"><code>{inspect(@click_count)}</code></strong>
    </p>
    """
  end

  def action(:record_click, _params, component) do
    put_state(component, :click_count, component.state.click_count + 1)
  end
end
