defmodule HologramFeatureTests.Components.Refs.Field do
  use Hologram.Component

  prop :field_ref, :any

  def template do
    ~HOLO"""
    <input type="text" id="refs_field" $ref={@field_ref} />
    """
  end
end
