defmodule HologramFeatureTests.Navigation.LeftListenersDestinationPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/navigation/left-listeners-destination/:kind"

  param :kind, :string

  layout HologramFeatureTests.Components.DefaultLayout

  # The param is copied into state so an action can report it: what a click puts on screen then
  # says which mount the page is running under, not merely that the patch drew the new markup.
  def init(params, component, _server) do
    component
    |> put_state(:mounted_with_kind, params.kind)
    |> put_state(:result, nil)
  end

  def template do
    ~HOLO"""
    <h1 id="destination_title">Left listeners destination title</h1>
    <button $click="put_result">Put destination result</button>
    <p>
      Result: <strong id="destination_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:put_result, _params, component) do
    put_state(component, :result, component.state.mounted_with_kind)
  end
end
