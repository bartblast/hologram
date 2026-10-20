defmodule HologramFeatureTests.Components.Rendering.DefaultInitComponent do
  use Hologram.Component

  prop :label, :string

  # No init/3 and no init/2 on purpose: this component relies on the defaults both on the server
  # and on the client, which is what the test checks.
  def template do
    ~HOLO"""
    <div id="{@cid}">{@label}</div>
    """
  end
end
