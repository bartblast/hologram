defmodule HologramFeatureTests.Cookies.Page3 do
  use Hologram.Page

  route "/cookies/3"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, _component, server) do
    put_cookie(server, "cookie_key", "cookie_value")
  end

  def template do
    ~HOLO""
  end
end
