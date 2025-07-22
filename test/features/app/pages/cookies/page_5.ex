defmodule HologramFeatureTests.Cookies.Page5 do
  use Hologram.Page

  route "/cookies/5"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, _component, server) do
    delete_cookie(server, "cookie_key")
  end

  def template do
    ~HOLO""
  end
end
