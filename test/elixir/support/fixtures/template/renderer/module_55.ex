# Used only in client tests.
defmodule Hologram.Test.Fixtures.Template.Renderer.Module55 do
  use Hologram.Component

  @impl Component
  def template do
    ~H"""
    <div>
      <button $click="my_action">Click me</button>
    </div>
    """
  end
end
