defmodule HologramFeatureTests.Rendering.PropsOnStructPage do
  use Hologram.Page

  alias HologramFeatureTests.Components.Rendering.PropsOnStructComponent

  route "/rendering/props-on-struct/:n"

  param :n, :integer

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    component
    |> put_state(:count, 0)
    |> put_state(:result, nil)
    |> put_state(:show_component_2, false)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="increment">Increment</button>
      <button $click="read_param">Read param</button>
      <button $click="show_component_2">Show component 2</button>
    </p>
    <p>
      Page result: <strong id="page_result">{inspect(@result)}</strong>
    </p>
    <PropsOnStructComponent cid="component_1" count={@count} />
    {%if @show_component_2}
      <PropsOnStructComponent cid="component_2" count={@count} />
    {/if}
    """
  end

  # Component 2 only enters the tree once the page is already loaded, so it initializes through
  # init/2 on the client rather than through init/3 on the server.
  def action(:show_component_2, _params, component) do
    put_state(component, :show_component_2, true)
  end

  def action(:increment, _params, component) do
    put_state(component, :count, component.state.count + 1)
  end

  # A page's params are its props, so the URL param is readable here without a copy in state.
  def action(:read_param, _params, component) do
    put_state(component, :result, component.props.n)
  end
end
