defmodule HologramFeatureTests.Navigation.Page3 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/navigation/3/:s/:i"

  param :s, :string
  param :i, :integer

  layout HologramFeatureTests.Components.DefaultLayout

  def init(params, component, _server) do
    put_state(component, :result, params)
  end

  def template do
    ~HOLO"""
    <h1>Page 3 title</h1>
    <button $click="put_result">Put page 3 result</button>
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:put_result, _params, component) do
    put_state(component, :result, "Page 3 result")
  end
end
