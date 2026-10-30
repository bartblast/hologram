defmodule HologramFeatureTests.ResponseHeaders.Page5 do
  use Hologram.Page

  route "/response-headers/5"

  layout HologramFeatureTests.Components.ResponseHeadersLayout

  middleware :mark

  def mark(server, _opts) do
    put_response_header(server, "x-set-by", "command middleware")
  end

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <h1>Response Headers / Page 5</h1>

    <button id="run_command" $click={command: :run, params: %{}}>run command</button>

    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def command(:run, _params, server) do
    put_action(server, :show, %{value: "page 5 command ran"})
  end

  def action(:show, params, component) do
    put_state(component, :result, params.value)
  end
end
