defmodule HologramFeatureTests.CallGraph.SharedFunctionsPage2 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.ModuleFixture4

  route "/call-graph/shared-functions-2"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="call_fun_b"> Call fun_b </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:call_fun_b, _params, component) do
    put_state(component, :result, ModuleFixture4.fun_b())
  end
end
