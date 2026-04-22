defmodule HologramFeatureTests.CallGraph.DynamicDispatchPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/call-graph/dynamic-dispatch"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="date_new"> Date.new </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:date_new, _params, component) do
    result = Date.new(2024, 6, 15)

    put_state(component, :result, result)
  end
end
