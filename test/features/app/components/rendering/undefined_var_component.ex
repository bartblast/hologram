defmodule HologramFeatureTests.Components.Rendering.UndefinedVarComponent do
  use Hologram.Component

  prop :label, :string

  def template do
    ~HOLO"""
    <p>{@label} / {@missing}</p>
    """
  end
end
