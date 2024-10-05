defmodule HologramFeatureTests.Navigation2Page do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/navigation-2"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~H"""
    <h1>Page 2 title</h1>
    <button $click="put_result">Put page 2 result</button>
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:put_result, _params, component) do
    put_state(component, :result, "Page 2 result")
  end
end
