defmodule HologramFeatureTests.Middleware.Page7 do
  use HologramFeatureTests.Middleware.BasePage

  route "/middleware/7"

  middleware :own

  def own(server, _opts) do
    put_stash(server, :own, "own step")
  end

  def init(_params, component, server) do
    put_state(component, :result, "#{get_stash(server, :shared)} / #{get_stash(server, :own)}")
  end

  def template do
    ~HOLO"""
    <h1>Middleware / Page 7</h1>

    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end
end
