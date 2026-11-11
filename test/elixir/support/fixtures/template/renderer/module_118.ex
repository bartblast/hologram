defmodule Hologram.Test.Fixtures.Template.Renderer.Module118 do
  use Hologram.Component

  prop :ref, :any, default: :shared

  @impl Component
  def template do
    ~HOLO"""
    <div $ref={@ref}></div><slot />
    """
  end
end
