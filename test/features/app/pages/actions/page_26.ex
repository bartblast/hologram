defmodule HologramFeatureTests.Actions.Page26 do
  use Hologram.Page
  use Hologram.JS

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.UI.Link
  alias HologramFeatureTests.Actions.Page27
  alias HologramFeatureTests.Components.Actions.Component22

  js_import from: "./helpers.mjs", as: :helpers

  route "/actions/26"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <h1>Page 26 title</h1>
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <button $click="await_forever">Await forever</button>
    </p>
    <p>
      <button $click="await_slowly">Await slowly</button>
    </p>
    <Component22 cid="component_22" />
    <Link to={Page27}>Page 27 link</Link>
    """
  end

  # A promise that never settles: a permission prompt nobody answers, a request with no timeout.
  def action(:await_forever, _params, component) do
    :helpers
    |> JS.call(:neverSettle, [])
    |> Task.await()

    put_state(component, :result, :never)
  end

  # Longer than the driver waits for an assertion, so a held component shows as a failed
  # assertion rather than as a late success.
  def action(:await_slowly, _params, component) do
    :helpers
    |> JS.call(:slowValue, [5000])
    |> Task.await()

    put_state(component, :result, :awaited_slowly)
  end
end
