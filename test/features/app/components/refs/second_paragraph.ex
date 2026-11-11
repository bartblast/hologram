defmodule HologramFeatureTests.Components.Refs.SecondParagraph do
  use Hologram.Component

  prop :paragraph_ref, :any

  def template do
    ~HOLO"""
    <p $ref={@paragraph_ref}>Second paragraph</p>
    """
  end
end
