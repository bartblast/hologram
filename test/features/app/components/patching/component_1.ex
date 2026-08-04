defmodule HologramFeatureTests.Components.Patching.Component1 do
  use Hologram.Component

  # Renders more than one root node on purpose: how many nodes a component contributes to its
  # caller's child list isn't knowable where the caller is compiled, so a conditional branch
  # holding one has no fixed size.
  def template do
    ~HOLO"""
    <div class="branch">component line 1</div>
    <div class="branch">component line 2</div>
    """
  end
end
