defmodule HologramFeatureTests.Actions.Page25 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Actions.Page24

  route "/actions/25"

  layout HologramFeatureTests.Components.DefaultLayout

  # Reaching page 24 through a link exercises the client-side path, where the runtime is already
  # up and the page's inline script dispatches while the page's own code is still loading.
  def template do
    ~HOLO"""
    <h1>Page 25 title</h1>
    <Link to={Page24, via: "link"}>Page 24 link</Link>
    """
  end
end
