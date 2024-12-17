defmodule HologramFeatureTests.Components.EmptyLayout do
  use Hologram.Component

  def template do
    ~H"<slot />"
  end
end
