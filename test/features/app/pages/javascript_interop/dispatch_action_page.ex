defmodule HologramFeatureTests.JavaScriptInterop.DispatchActionPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/js-interop/dispatch-action"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      Call result: <strong id="call_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:dispatch_with_params, params, component) do
    put_state(component, :result, {params.amount, params.label})
  end

  def action(:dispatch_without_params, _params, component) do
    put_state(component, :result, :dispatched)
  end
end
