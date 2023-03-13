defmodule Hologram.Test.Fixtures.Template.PageRenderer.Module3 do
  use Hologram.Component

  def init(_props) do
    %{
      component_3_state_key: "component_3_state_value"
    }
  end

  def template do
    ~H"""
    (in component 3)
    """
  end
end
