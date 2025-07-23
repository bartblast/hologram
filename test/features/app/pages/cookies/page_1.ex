defmodule HologramFeatureTests.Cookies.Page1 do
  use Hologram.Page

  route "/cookies/1"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, server) do
    put_state(component, :result, get_cookie(server, "cookie_key"))
  end

  def template do
    ~HOLO"""
    <h1>Cookies / Page 1</h1>

    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p> 
    """
  end
end
