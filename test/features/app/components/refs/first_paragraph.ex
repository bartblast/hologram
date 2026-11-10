defmodule HologramFeatureTests.Components.Refs.FirstParagraph do
  use Hologram.Component

  prop :paragraph_ref, :any

  def template do
    ~HOLO"""
    <p $ref={@paragraph_ref}>First paragraph</p>
    """
  end
end
