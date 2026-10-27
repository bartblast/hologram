defmodule HologramFeatureTests.ResponseHeaders.Page4 do
  use Hologram.Page

  route "/response-headers/4"

  layout HologramFeatureTests.Components.ResponseHeadersLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <h1>Response Headers / Page 4</h1>

    <button id="run_command" $click={command: :mark, params: %{}}>run command</button>

    <p>
      Result: <strong id="result"><code>{@result}</code></strong>
    </p>
    """
  end

  def command(:mark, _params, server) do
    server
    |> put_response_header("x-set-by", "command")
    |> put_action(:show, %{value: "page 4 command ran"})
  end

  def action(:show, params, component) do
    put_state(component, :result, params.value)
  end
end
