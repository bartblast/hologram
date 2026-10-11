defmodule HologramFeatureTests.Actions.Page27 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/actions/27"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <h1>Page 27 title</h1>
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <button $click="put_result">Put page 27 result</button>
    </p>
    """
  end

  def action(:put_result, _params, component) do
    put_state(component, :result, "Page 27 result")
  end
end
