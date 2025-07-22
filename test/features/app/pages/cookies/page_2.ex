defmodule HologramFeatureTests.Cookies.Page2 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/cookies/2"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, server) do
    result =
      server
      |> get_cookie("cookie_key")
      |> Map.put(:c, 3)

    put_state(component, :result, result)
  end

  def template do
    ~HOLO"""
    <h1>Cookies / Page 2</h1>

    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p> 
    """
  end
end
