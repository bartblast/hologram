defmodule HologramFeatureTests.JavaScriptInterop.PendingActionsPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/js-interop/pending-actions"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <script>
      Hologram.dispatchAction("dispatch_pending", "page", \{value: 99\});
    </script>
    <p>
      Call result: <strong id="call_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:dispatch_pending, params, component) do
    put_state(component, :result, {params.value, is_integer(params.value)})
  end
end
