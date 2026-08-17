defmodule HologramFeatureTests.Navigation.Page7 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/navigation/7"

  layout HologramFeatureTests.Components.NavigationLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <h1>Page 7 title</h1>
    <button $click="put_result">Put page 7 result</button>
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:put_result, _params, component) do
    put_state(component, :result, "Page 7 result")
  end
end
