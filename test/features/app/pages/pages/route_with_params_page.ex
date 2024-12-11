defmodule HologramFeatureTests.Pages.RouteWithParamsPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/pages/route-with-params/:a/:b"

  param :a, :string
  param :b, :integer

  layout HologramFeatureTests.Components.DefaultLayout

  def init(params, component, _server) do
    put_state(component, :result, params)
  end

  def template do
    ~H"""
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>    
    """
  end
end
