defmodule HologramFeatureTests.Security.Page2 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/security/2"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <div>
      <h1>Security / Page 2</h1>
      <p>
        <button $click={:test_action_2, m: 300}>
          Test Action 2
        </button>
      </p>
      <p>
        Result: <strong id="result"><code>{inspect(@result)}</code></strong>
      </p>      
    </div>
    """
  end

  def action(:test_action_2, params, component) do
    put_state(component, :result, params.m + 1)
  end
end
