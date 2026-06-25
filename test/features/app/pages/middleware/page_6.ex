defmodule HologramFeatureTests.Middleware.Page6 do
  use Hologram.Page

  alias HologramFeatureTests.Middleware.Shared

  route "/middleware/6"

  layout HologramFeatureTests.Components.DefaultLayout

  middleware Shared
  middleware :inline

  def inline(server, _opts) do
    put_stash(server, :inline, "inline middleware")
  end

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <h1>Middleware / Page 6</h1>

    <button id="run_command" $click={command: :read_middleware, params: %{}}>run command</button>

    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def command(:read_middleware, _params, server) do
    result = "#{get_stash(server, :shared)} / #{get_stash(server, :inline)}"
    put_action(server, :show_middleware, %{value: result})
  end

  def action(:show_middleware, params, component) do
    put_state(component, :result, params.value)
  end
end
