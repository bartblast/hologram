defmodule HologramFeatureTests.Middleware.Page1 do
  use Hologram.Page

  route "/middleware/1"

  layout HologramFeatureTests.Components.DefaultLayout

  def middleware(server) do
    put_stash(server, :marker, "enriched by middleware")
  end

  def init(_params, component, server) do
    put_state(component, :result, get_stash(server, :marker))
  end

  def template do
    ~HOLO"""
    <h1>Middleware / Page 1</h1>

    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end
end
