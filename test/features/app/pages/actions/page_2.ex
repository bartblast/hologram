defmodule HologramFeatureTests.Actions.Page2 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/actions/2"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    component
    |> put_state(:result, nil)
    |> put_action(:page_action, queued_from: "page")
  end

  def template do
    ~HOLO"""
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:page_action, params, component) do
    put_state(component, :result, {:page_action_result, params})
  end
end
