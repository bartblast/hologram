defmodule HologramFeatureTests.Navigation1Page do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.UI.Link
  alias HologramFeatureTests.Navigation2Page, as: Page2
  alias HologramFeatureTests.Navigation3Page, as: Page3

  route "/navigation-1"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~H"""
    <h1>Page 1 title</h1>
    <button $click="put_result">Put page 1 result</button>
    <button $click="change_page">Change page</button>
    <Link to={Page2}>Page 2 link</Link>
    <Link to={Page3, s: "abc", i: 123}>Page 3 link</Link>
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:change_page, _params, component) do
    put_page(component, Page2)
  end

  def action(:put_result, _params, component) do
    put_state(component, :result, "Page 1 result")
  end
end
