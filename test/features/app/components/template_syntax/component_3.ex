defmodule HologramFeatureTests.Components.TemplateSyntax.Component3 do
  use Hologram.Component

  prop :dom_id, :string

  def init(_props, component, _server) do
    put_state(component, :my_state_value, "value_7")
  end

  def template do
    ~HOLO"""
    <div id={@dom_id}>my_state_value = {@my_state_value}</div>
    """
  end
end
