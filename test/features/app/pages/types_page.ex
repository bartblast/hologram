defmodule HologramFeatureTests.TypesPage do
  use Hologram.Page
  import HologramFeatureTests.Commons

  route "/types"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~H"""
    <p>
      <button id="anonymous function (client origin, non-capture)" $click="anonymous function (client origin, non-capture)"> anonymous function (client origin, non-capture) </button>
      <button id="anonymous function (client origin, capture)" $click="anonymous function (client origin, capture)"> anonymous function (client origin, capture) </button>
      <button id="anonymous function (server origin, non-capture)" $click={%Command{name: :"anonymous function (server origin, non-capture)"}}> anonymous function (server origin, non-capture) </button>
    </p>
    <p>
      <button id="atom" $click="atom"> atom </button>
      <button id="bitstring (binary)" $click="bitstring (binary)"> bitstring (binary) </button>
      <button id="bitstring (non-binary)" $click="bitstring (non-binary)"> bitstring (non-binary) </button>
      <button id="float" $click="float"> float </button>
      <button id="integer" $click="integer"> integer </button>
      <button id="list" $click="list"> list </button>
      <button id="map" $click="map"> map </button>
      <button id="pid (client origin)" $click="pid (client origin)"> pid (client origin) </button>
      <button id="pid (server origin)" $click={%Command{name: :"pid (server origin)"}}> pid (server origin) </button>
      <button id="tuple" $click="tuple"> tuple </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:"anonymous function (client origin, non-capture)", _params, component) do
    term = fn x, y -> x * y end
    result = term.(2, 3)

    component
    |> put_state(:result, result)
    |> put_command(:echo, term: term)
  end

  def action(:"anonymous function (client origin, capture)", _params, component) do
    term = &my_fun/2
    result = term.(2, 3)

    component
    |> put_state(:result, result)
    |> put_command(:"anonymous function (client origin, capture)", term: term)
  end

  def action(:"anonymous function (client origin, capture) echo", params, component) do
    result = params.term.(2, 3)
    put_state(component, :result, result)
  end

  def action(:atom, _params, component) do
    term = :abc
    put_command(component, :echo, term: term)
  end

  def action(:"bitstring (binary)", _params, component) do
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

  def action(:"pid (client origin)", _params, component) do
    term = pid("0.11.222")
    put_command(component, :echo, term: term)
  end

  def action(:"pid (server origin)", params, component) do
    put_state(component, :result, params.term)
  end

  def action(:tuple, _params, component) do
    term = {123, :abc}
    put_command(component, :echo, term: term)
  end

  def action(:result, params, component) do
    put_state(component, :result, params.term)
  end

  def command(:echo, params, server) do
    put_action(server, :result, params)
  end

  def command(:"anonymous function (client origin, capture)", params, server) do
    put_action(server, :"anonymous function (client origin, capture) echo", params)
  end

  def command(:"anonymous function (server origin, non-capture)", _params, server) do
    term = fn x, y -> x * y end
    put_action(server, :result, term: term)
  end

  def command(:"pid (server origin)", _params, server) do
    term = pid("0.11.222")
    put_action(server, :"pid (server origin)", term: term)
  end

  def my_fun(x, y), do: x * y
end
