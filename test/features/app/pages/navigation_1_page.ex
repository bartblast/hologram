defmodule HologramFeatureTests.Navigation1Page do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.UI.Link
  alias HologramFeatureTests.Navigation2Page

  route "/navigation-1"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~H"""
    <h1>Page 1 title</h1>
    <Link to={Navigation2Page}>Page 2 link</Link>
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>    
    """
  end
end
