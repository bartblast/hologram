# The three shared-functions pages reach different subsets of ModuleFixture4's functions, so
# that a page ships exactly the functions it reaches no matter which page's build encoded the
# module first.
defmodule HologramFeatureTests.CallGraph.SharedFunctionsPage1 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.ModuleFixture4

  route "/call-graph/shared-functions-1"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="call_fun_a"> Call fun_a </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:call_fun_a, _params, component) do
    put_state(component, :result, ModuleFixture4.fun_a())
  end
end
