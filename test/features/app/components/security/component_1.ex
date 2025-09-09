defmodule HologramFeatureTests.Components.Security.Component1 do
  use Hologram.Component

  prop :my_value, :string

  def template do
    ~HOLO"""
    <form>
      <input type="text" id="text_input" value={@my_value} />
    </form>
    """
  end
end
