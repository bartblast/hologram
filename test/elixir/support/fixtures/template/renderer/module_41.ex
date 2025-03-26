defmodule Hologram.Test.Fixtures.Template.Renderer.Module41 do
  use Hologram.Component

  prop :aaa, :integer, from_context: {:my_scope, :my_key}

  @impl Component
  def template do
    ~HOLO"""
    prop_aaa = {@aaa}
    """
  end
end
