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
      <button id="atom" $click="atom"> atom </button>
      <button id="float" $click="float"> float </button>
      <button id="integer" $click="integer"> integer </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:atom, _params, component) do
    term = :abc
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

  def action(:result, params, component) do
    put_state(component, :result, params.term)
  end

  def command(:echo, params, server) do
    put_action(server, :result, params)
  end
end
