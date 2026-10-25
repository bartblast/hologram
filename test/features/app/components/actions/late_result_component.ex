defmodule HologramFeatureTests.Components.Actions.LateResultComponent do
  use Hologram.Component
  use Hologram.JS

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  js_import from: "../../pages/actions/helpers.mjs", as: :helpers

  # Mounted on the late result page only, so its cid is registered nowhere once the user has
  # navigated away. A result that survives then has no struct to replace, and the registry write
  # faults with a raw TypeError, which the error overlay does not show but the browser log records.
  def init(_props, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="slow_component_action">Run slow component action</button>
      Component result: <strong id="component_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  # Stands in for a slow fetch: the await is still pending after the user has navigated away.
  def action(:slow_component_action, _params, component) do
    :helpers
    |> JS.call(:slowValue, [3000])
    |> Task.await()

    put_state(component, :result, "component_result_ran")
  end
end
