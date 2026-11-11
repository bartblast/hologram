defmodule HologramFeatureTests.Actions.Page24 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/actions/24/:via"

  param :via, :string

  layout HologramFeatureTests.Components.DefaultLayout

  state :log, :list

  # The page starts an action in both of the ways a page can: one queued here, one dispatched by
  # the script in its template.
  def init(_params, component, _server) do
    component
    |> put_state(log: [])
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
    put_state(component, :log, component.state.log ++ [init: component.props.via])
  end

  def action(:append_from_script, _params, component) do
    put_state(component, :log, component.state.log ++ [script: component.props.via])
  end
end
