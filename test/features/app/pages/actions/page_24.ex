defmodule HologramFeatureTests.Actions.Page24 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/actions/24/:via"

  param :via, :string

  layout HologramFeatureTests.Components.DefaultLayout

  # The page starts an action in both of the ways a page can: one queued here, one dispatched by
  # the script in its template.
  def init(params, component, _server) do
    component
    |> put_state(log: [], via: params.via)
    |> put_action(:append_from_init)
  end

  def template do
    ~HOLO"""
    <script>
      Hologram.dispatchAction("append_from_script", "page");
    </script>
    <h1>Page 24 title</h1>
    <p>
      Log: <strong id="log"><code>{inspect(@log)}</code></strong>
    </p>
    """
  end

  def action(:append_from_init, _params, component) do
    put_state(component, :log, component.state.log ++ [init: component.state.via])
  end

  def action(:append_from_script, _params, component) do
    put_state(component, :log, component.state.log ++ [script: component.state.via])
  end
end
