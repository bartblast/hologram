defmodule HologramFeatureTests.Cookies.PageInitPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/cookies/page-init"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, server) do
    put_state(component, :result, get_cookie(server, "cookie_key"))
  end

  def template do
    ~HOLO"""
    <h1>Page Init Cookies Tests</h1>

    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p> 
    """
  end
end
