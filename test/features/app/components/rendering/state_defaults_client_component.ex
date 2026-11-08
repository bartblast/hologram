defmodule HologramFeatureTests.Components.Rendering.StateDefaultsClientComponent do
  use Hologram.Component

  # A module of its own, rendered only once the page is loaded, so the value it shows can only come
  # from its declared default seeding its state on the client. No init/2 on purpose.
  state :greeting, :string, default: "client component default"

  def template do
    ~HOLO"""
    <div id="{@cid}">{@greeting}</div>
    """
  end
end
