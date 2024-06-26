defmodule HologramFeatureTests.TypesPage do
  use Hologram.Page

  route "/types"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~H"""
    <p>
      <button id="anonymous_function_client" $click="anonymous_function_client"> anonymous_function_client </button>
      <button id="anonymous_function_transport" $click="anonymous_function_transport"> anonymous_function_transport </button>
      <button id="atom" $click="atom"> atom </button>
      <button id="binary" $click="binary"> binary </button>
      <button id="bitstring (non-binary)" $click="bitstring (non-binary)"> bitstring (non-binary) </button>
      <button id="float" $click="float"> float </button>
      <button id="integer" $click="integer"> integer </button>
      <button id="list" $click="list"> list </button>
      <button id="map" $click="map"> map </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:anonymous_function_client, _params, component) do
    term = fn x -> x * x end
    result = term.(2)

    put_state(component, :result, result)
  end

  def action(:anonymous_function_transport, _params, component) do
    term = fn x -> x * x end
    put_command(component, :echo, term: term)
  end

  def action(:atom, _params, component) do
    term = :abc
    put_command(component, :echo, term: term)
  end

  def action(:binary, _params, component) do
    term = "abc"
    put_command(component, :echo, term: term)
  end

  def action(:"bitstring (non-binary)", _params, component) do
    term = <<1::1, 0::1, 1::1, 0::1>>
    put_command(component, :echo, term: term)
  end

  def action(:float, _params, component) do
    term = 1.23
    put_command(component, :echo, term: term)
  end

  def action(:integer, _params, component) do
    term = 123
    put_command(component, :echo, term: term)
  end

  def action(:list, _params, component) do
    term = [123, :abc]
    put_command(component, :echo, term: term)
  end

  def action(:map, _params, component) do
    term = %{a: 123, b: "abc"}
    put_command(component, :echo, term: term)
  end

  def action(:result, params, component) do
    put_state(component, :result, params.term)
  end

  def command(:echo, params, server) do
    put_action(server, :result, params)
  end
end
