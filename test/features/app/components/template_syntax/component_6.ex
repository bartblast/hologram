defmodule HologramFeatureTests.Components.TemplateSyntax.Component6 do
  use Hologram.Component

  prop :dom_id, :string

  def template do
    ~HOLO"""
    <div id={@dom_id}>loaded from command</div>
    """
  end
end
