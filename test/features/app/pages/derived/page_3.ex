defmodule HologramFeatureTests.Derived.Page3 do
  use Hologram.Page

  alias Hologram.UI.Link
  alias HologramFeatureTests.Derived.Page4

  route "/derived/3"

  layout HologramFeatureTests.Components.DefaultLayout

  # The page a stream connects on, and the way to the page the counts are on, which a link reaches
  # while the stream is still filling.
  def template do
    ~HOLO"""
    <p>
      <Link to={Page4}>Ticket counts link</Link>
    </p>
    """
  end
end
