defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module6 do
  use Hologram.Component
  alias Hologram.Test.Fixtures.Template.ComponentRenderer.Module7, warn: false

  def init(_props) do
    %{
      parent_component_state_key: "parent_component_state_value"
    }
  end

  def template do
    ~H"""
    parent_head.<Module7 id="child_component" />.parent_tail
    """
  end
end
