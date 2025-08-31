defmodule Hologram.Test.Fixtures.Template.Renderer.Module78 do
  use Hologram.Component

  prop :aaa, :integer, from_context: {:my_scope, :my_key}, default: 987

  @impl Component
  def template do
    ~HOLO"""
    prop_aaa = {inspect(@aaa)}
    """
  end
end
