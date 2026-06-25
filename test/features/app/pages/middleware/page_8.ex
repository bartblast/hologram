defmodule HologramFeatureTests.Middleware.Page8 do
  use Hologram.Page

  alias HologramFeatureTests.Middleware.Group

  route "/middleware/8"

  layout HologramFeatureTests.Components.DefaultLayout

  middleware Group

  def init(_params, component, server) do
    put_state(component, :result, "#{get_stash(server, :shared)} / #{get_stash(server, :group)}")
  end

  def template do
    ~HOLO"""
    <h1>Middleware / Page 8</h1>

    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end
end
