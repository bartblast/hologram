defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module8 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Template.ComponentRenderer.Module9, warn: false

  def init(_props) do
    %{
      component_8_state_key: "component_8_state_value"
    }
  end

  def template do
    ~H"""
    abc<Module9 id="component_9_id" />xyz
    """
  end
end
