defmodule HologramFeatureTests.Pages.RouteWithoutParamsPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/pages/route-without-params"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(params, component, _server) do
    put_state(component, :result, params)
  end

  def template do
    ~H"""
    <p>
      Page params: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>    
    """
  end
end
