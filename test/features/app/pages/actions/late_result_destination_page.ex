defmodule HologramFeatureTests.Actions.LateResultDestinationPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.UI.Link
  alias HologramFeatureTests.Actions.LateResultPage

  route "/actions/late-result-destination"

  layout HologramFeatureTests.Components.LateResultLayout

  # Has the late result page's :result key and renders it, so a surviving page result shows here.
  # Has no component with the late result component's cid and defines no command, so a surviving
  # component result or command raises. The layout is shared, so a surviving layout result lands on
  # this page's layout.
  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <h1>Late result destination title</h1>
    <p>
      Page result: <strong id="page_result"><code>{inspect(@result)}</code></strong>
    </p>
    <Link to={LateResultPage}>Late result link</Link>
    """
  end
end
