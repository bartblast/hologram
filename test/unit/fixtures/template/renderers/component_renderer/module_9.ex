defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module9 do
  use Hologram.Component

  def init(_props) do
    %{
      component_9_state_key: "component_9_state_value"
    }
  end

  def template do
    ~H"""
    (in component 9: {@__context__.test_context_key})
    """
  end
end
