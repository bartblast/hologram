defmodule HologramCowboyTests.CommandPage do
  use Hologram.Page

  route "/command"

  layout HologramCowboyTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, "none")
  end

  def template do
    ~HOLO"""
    <p>Result: <strong id="result">{@result}</strong></p>
    <button id="run" $click={command: :run, params: %{value: 42}}>Run</button>
    """
  end

  def action(:show, params, component) do
    put_state(component, :result, "answered with #{params[:value]}")
  end

  def command(:run, params, server) do
    put_action(server, :show, value: params[:value])
  end
end
