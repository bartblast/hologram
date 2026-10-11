defmodule HologramFeatureTests.Actions.Page23 do
  use Hologram.Page
  use Hologram.JS

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  js_import from: "./helpers.mjs", as: :helpers

  route "/actions/23"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, count: 0, log: [])
  end

  def template do
    ~HOLO"""
    <h1>Page 23 title</h1>
    <p>
      Count: <strong id="count"><code>{inspect(@count)}</code></strong>
    </p>
    <p>
      Log: <strong id="log"><code>{inspect(@log)}</code></strong>
    </p>
    <p>
      <button id="append_fast" $click="append_fast">Append fast</button>
    </p>
    <p>
      <button id="append_slow" $click="append_slow">Append slow</button>
    </p>
    <p>
      <button id="increment" $click="increment">Increment</button>
    </p>
    """
  end

  def action(:append_fast, _params, component) do
    put_state(component, :log, component.state.log ++ [:fast])
  end

  # The await makes the whole action/3 asynchronous, the two synchronous clauses included: what
  # they compute is committed a tick later than it is read.
  def action(:append_slow, _params, component) do
    :helpers
    |> JS.call(:slowValue, [500])
    |> Task.await()

    put_state(component, :log, component.state.log ++ [:slow])
  end

  def action(:increment, _params, component) do
    put_state(component, :count, component.state.count + 1)
  end
end
