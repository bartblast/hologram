defmodule Hologram.Test.Fixtures.Template.Renderer.Module38 do
  use Hologram.Component

  prop :aaa, :integer, from_context: {:my_scope, :my_key}

  @impl Component
  def template do
    ~H"""
    prop_aaa = {@aaa}
    """
  end
end
