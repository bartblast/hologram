defmodule HologramFeatureTests.Components.EmptyLayout do
  use Hologram.Component

  def template do
    ~HOLO"<slot />"
  end
end
