defmodule HologramFeatureTests.Actions.Page22 do
  use Hologram.Page
  use Hologram.JS

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.UI.Link
  alias HologramFeatureTests.Actions.Page21

  js_import from: "./helpers.mjs", as: :helpers

  route "/actions/22"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <h1>Page 22 title</h1>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <button $click="run_async_continuation_action">Run async continuation action</button>
    </p>
    <Link to={Page21}>Page 21 link</Link>
    """
  end

  # The await gives whatever the user does next time to happen before the continuation is
  # scheduled - navigating away being the case under test.
  def action(:run_async_continuation_action, _params, component) do
    :helpers
    |> JS.call(:slowValue, [2000])
    |> Task.await()

    put_action(component, :async_continuation_action)
  end

  def action(:async_continuation_action, _params, component) do
    put_state(component, :result, :async_continuation_ran)
  end
end
