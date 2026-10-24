defmodule HologramFeatureTests.Commands.LateReplyDestinationPage do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Commands.LateReplyPage

  route "/commands/late-reply-destination"

  layout HologramFeatureTests.Components.LateReplyLayout

  # Has no component with the late reply component's cid and defines no action at all, so a
  # component or page reply that survives the navigation to here raises. The layout is shared, so a
  # layout reply would land on this page's layout instead.
  def template do
    ~HOLO"""
    <h1>Late reply destination title</h1>
    <Link to={LateReplyPage}>Late reply link</Link>
    """
  end
end
