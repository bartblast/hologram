defmodule Hologram.Test.Fixtures.Template.Renderer.Module94 do
  use Hologram.Component

  prop :body, :any

  @impl Component
  def template do
    ~HOLO"""
    <div>{@body}</div>
    """
  end
end
