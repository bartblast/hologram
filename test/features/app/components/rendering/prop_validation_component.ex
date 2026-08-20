defmodule HologramFeatureTests.Components.Rendering.PropValidationComponent do
  use Hologram.Component

  prop :label, :string, required: true
  prop :size, :atom, values: [:small, :large]

  def template do
    ~HOLO"""
    <p id="prop_validation_result">{@label} / {@size}</p>
    """
  end
end
