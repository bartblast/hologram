defmodule Hologram.Test.Fixtures.Template.ElementNodeRenderer.Module1 do
  use Hologram.Component

  def init(_props) do
    %{
      component_1_state_key: "component_1_state_value"
    }
  end

  def template do
    ~H"""
    (in component 1)
    """
  end
end
