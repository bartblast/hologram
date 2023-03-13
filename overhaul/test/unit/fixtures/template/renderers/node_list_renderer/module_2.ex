defmodule Hologram.Test.Fixtures.Template.NodeListRenderer.Module2 do
  use Hologram.Component

  def init(_props) do
    %{
      component_2_state_key: "component_2_state_value"
    }
  end

  def template do
    ~H"""
    (in component 2)
    """
  end
end
