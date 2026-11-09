defmodule HologramFeatureTests.Components.Rendering.StateDefaultsComponent do
  use Hologram.Component

  # No init/3 on purpose: the declared default is the state the component starts with.
  state :greeting, :string, default: "server component default"

  def template do
    ~HOLO"""
    <div id="{@cid}">{@greeting}</div>
    """
  end
end
