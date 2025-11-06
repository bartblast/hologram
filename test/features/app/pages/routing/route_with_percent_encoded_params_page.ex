defmodule HologramFeatureTests.Routing.RouteWithPercentEncodedParamsPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/routing/route-with-percent-encoded-params/:a/:b"

  param :a, :string
  param :b, :string

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <h1>Route With Percent Encoded Params Page</h1>
    <p>
      param a = <strong id="param_a"><code>{inspect(@a)}</code></strong>
    </p>
    <p>
      param b = <strong id="param_b"><code>{inspect(@b)}</code></strong>
    </p>
    """
  end
end
