defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module7 do
  use Hologram.Component

  def init(_props) do
    %{
      child_component_state_key: "child_component_state_value"
    }
  end

  def template do
    ~H"""
    child
    """
  end
end
