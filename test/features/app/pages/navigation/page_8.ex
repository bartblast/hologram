defmodule HologramFeatureTests.Navigation.Page8 do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.UI.Link
  alias HologramFeatureTests.Navigation.Page8

  route "/navigation/8/:n"

  param :n, :integer

  layout HologramFeatureTests.Components.DefaultLayout

  # Links to itself with the next param value, which is the navigation that lands on a page whose
  # code this client has already run.
  #
  # The param is copied into state so an action can report it: what a click puts on screen then
  # says which mount the page is running under, not merely that the patch drew the new markup.
  def init(params, component, _server) do
    component
    |> put_state(:mounted_with_n, params.n)
    |> put_state(:result, nil)
  end

  def template do
    ~HOLO"""
    <h1>Page 8 title</h1>
    <p>
      Param n: <strong id="param_n">{@n}</strong>
    </p>
    <Link to={Page8, n: @n + 1}>Page 8 next link</Link>
    <button $click="put_result">Put page 8 result</button>
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:put_result, _params, component) do
    put_state(component, :result, component.state.mounted_with_n)
  end
end
