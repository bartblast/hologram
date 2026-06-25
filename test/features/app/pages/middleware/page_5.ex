defmodule HologramFeatureTests.Middleware.Page5 do
  use Hologram.Page

  alias HologramFeatureTests.MiddlewareFixture

  route "/middleware/5"

  layout HologramFeatureTests.Components.DefaultLayout

  middleware MiddlewareFixture
  middleware :inline

  def inline(server, _opts) do
    put_stash(server, :inline, "inline step")
  end

  def init(_params, component, server) do
    put_state(component, :result, "#{get_stash(server, :shared)} / #{get_stash(server, :inline)}")
  end

  def template do
    ~HOLO"""
    <h1>Middleware / Page 5</h1>

    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end
end
