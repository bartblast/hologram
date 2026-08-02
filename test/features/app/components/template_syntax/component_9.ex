defmodule HologramFeatureTests.Components.TemplateSyntax.Component9 do
  use Hologram.Component

  prop :dom_id, :string

  def template do
    ~HOLO"""
    <div id={@dom_id}>delivered from broadcast</div>
    """
  end
end
