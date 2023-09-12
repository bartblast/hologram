defmodule Hologram.Test.Fixtures.Template.Renderer.Module41 do
  use Hologram.Layout

  prop :aaa, :integer, from_context: {:my_scope, :my_key}

  @impl Layout
  def template do
    ~H"""
    prop_aaa = {@aaa}
    """
  end
end
