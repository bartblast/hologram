defmodule HologramFeatureTests.TypesPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.Commons.TestUtils, only: [pid: 1]
  import Kernel, except: [inspect: 1]

  route "/types"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button id="anonymous function (client origin, non-capture)" $click="anonymous function (client origin, non-capture)"> anonymous function (client origin, non-capture) </button>
      <button id="anonymous function (server origin, non-capture)" $click={command: :"anonymous function (server origin, non-capture)"}> anonymous function (server origin, non-capture) </button>
      <button id="anonymous function (client origin, capture)" $click="anonymous function (client origin, capture)"> anonymous function (client origin, capture) </button>
      <button id="anonymous function (server origin, capture)" $click={command: :"anonymous function (server origin, capture)"}> anonymous function (server origin, capture) </button>
    </p>
    <p>
      <button id="local function capture (client origin)" $click="local function capture (client origin)"> local function capture (client origin) </button>
      <button id="local function capture (server origin)" $click={command: :"local function capture (server origin)"}> local function capture (server origin) </button>
      <button id="remote function capture (client origin)" $click="remote function capture (client origin)"> remote function capture (client origin) </button>
      <button id="remote function capture (server origin)" $click={command: :"remote function capture (server origin)"}> remote function capture (server origin) </button>
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
      <button id="pid (server origin)" $click={command: :"pid (server origin)"}> pid (server origin) </button>
      <button id="tuple" $click="tuple"> tuple </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:"anonymous function (client origin, non-capture)", _params, component) do
    term = fn x, y -> x * y + x end
    result = term.(2, 3)

    component
    |> put_state(:result, result)
    |> put_command(:echo, term: term)
  end

  def action(:"anonymous function (client origin, capture)", _params, component) do
    term = &(&1 * &2 + &1)
    result = term.(2, 3)

    component
    |> put_state(:result, result)
    |> put_command(:echo, term: term)
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

  def action(:"local function capture (client origin)", _params, component) do
    term = &my_fun/2
    result = "client = #{term.(2, 3)}"

    component
    |> put_state(:result, result)
    |> put_command(:"local function capture (client origin) echo", term: term)
  end

  def action(:"local function capture (client origin) result", params, component) do
    result = component.state.result <> ", server = #{params.term.(2, 3)}"
    put_state(component, :result, result)
  end

  def action(:"local function capture (server origin) result", params, component) do
    result = params.term.(2, 3)
    put_state(component, :result, result)
  end

  def action(:map, _params, component) do
    term = %{a: 123, b: "abc"}
    put_command(component, :echo, term: term)
  end

  def action(:"pid (client origin)", _params, component) do
    term = pid("0.11.222")
    put_command(component, :echo, term: term)
  end

  def action(:"pid (server origin) result", params, component) do
    put_state(component, :result, params.term)
  end

  def action(:"remote function capture (client origin)", _params, component) do
    term = &HologramFeatureTests.TypesPage.my_fun/2
    result = "client = #{term.(2, 3)}"

    component
    |> put_state(:result, result)
    |> put_command(:"remote function capture (client origin) echo", term: term)
  end

  def action(:"remote function capture (client origin) result", params, component) do
    result = component.state.result <> ", server = #{params.term.(2, 3)}"
    put_state(component, :result, result)
  end

  def action(:"remote function capture (server origin) result", params, component) do
    result = params.term.(2, 3)
    put_state(component, :result, result)
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

  def command(:"anonymous function (server origin, non-capture)", _params, server) do
    term = fn x, y -> x * y + x end
    put_action(server, :result, term: term)
  end

  def command(:"anonymous function (server origin, capture)", _params, server) do
    term = &(&1 * &2 + &1)
    put_action(server, :result, term: term)
  end

  def command(:"local function capture (client origin) echo", params, server) do
    put_action(server, :"local function capture (client origin) result", params)
  end

  def command(:"local function capture (server origin)", _params, server) do
    term = &my_fun/2
    put_action(server, :"local function capture (server origin) result", term: term)
  end

  def command(:"pid (server origin)", _params, server) do
    term = pid("0.11.222")
    put_action(server, :"pid (server origin) result", term: term)
  end

  def command(:"remote function capture (client origin) echo", params, server) do
    put_action(server, :"remote function capture (client origin) result", params)
  end

  def command(:"remote function capture (server origin)", _params, server) do
    term = &HologramFeatureTests.TypesPage.my_fun/2
    put_action(server, :"remote function capture (server origin) result", term: term)
  end

  def my_fun(x, y), do: x * y + x
end
