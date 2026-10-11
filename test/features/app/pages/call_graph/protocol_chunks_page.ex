# The page exists so a test can navigate from it into a page whose initial state holds a struct:
# the destination's chunks then arrive with the navigation's payload, not with a document. It must
# name no struct fixture, so that the tab holds none of their chunks before the navigation.
defmodule HologramFeatureTests.CallGraph.ProtocolChunksPage do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.CallGraph.ServerCreatedStructsPage

  route "/call-graph/protocol-chunks"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <p>
      <Link to={ServerCreatedStructsPage}>Server created structs</Link>
    </p>
    """
  end
end
