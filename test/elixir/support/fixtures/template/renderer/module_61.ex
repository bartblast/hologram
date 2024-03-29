# Used only in client tests.
defmodule Hologram.Test.Fixtures.Template.Renderer.Module61 do
  use Hologram.Component

  @impl Component
  def template do
    ~H"""
    <div>
      <slot />
    </div>
    """
  end
end
