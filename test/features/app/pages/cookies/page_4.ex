defmodule HologramFeatureTests.Cookies.Page4 do
  use Hologram.Page

  route "/cookies/4"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, _component, server) do
    opts = [
      http_only: false,
      path: __MODULE__.__route__(),
      same_site: :strict,
      secure: false
    ]

    put_cookie(server, "cookie_key", "cookie_value", opts)
  end

  def template do
    ~HOLO""
  end
end
