defmodule HologramFeatureTests.Security.Page6 do
  use Hologram.Page
  alias HologramFeatureTests.Components.Security.Component1

  route "/security/6"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, my_value: nil)
  end

  def template do
    ~HOLO"""
    <Component1 my_value={@my_value} />

    <p>
      <button $click="set_prop_value">Set prop value</button>
    </p>
    """
  end

  def action(:set_prop_value, _params, component) do
    put_state(component, my_value: "a < b")
  end
end
