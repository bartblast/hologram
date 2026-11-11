defmodule Hologram.Test.Fixtures.Template.Renderer.Module119 do
  use Hologram.Component

  prop :ref, :any

  @impl Component
  def template do
    ~HOLO"""
    <div $ref={@ref}></div>
    """
  end
end
