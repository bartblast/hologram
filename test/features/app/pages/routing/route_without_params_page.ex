defmodule HologramFeatureTests.Routing.RouteWithoutParamsPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/routing/route-without-params"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(params, component, _server) do
    put_state(component, module: __MODULE__, params: params)
  end

  def template do
    ~HOLO"""
    <p>
      Page module: <strong id="page_module"><code>{inspect(@module)}</code></strong>
    </p>       
    <p>
      Page params: <strong id="page_params"><code>{inspect(@params)}</code></strong>
    </p>    
    """
  end
end
