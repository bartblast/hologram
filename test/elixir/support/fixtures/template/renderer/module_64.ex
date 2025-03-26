defmodule Hologram.Test.Fixtures.Template.Renderer.Module64 do
  use Hologram.Component

  prop :my_prop, :any

  @impl Component
  def template do
    ~HOLO"my_prop = {inspect(@my_prop)}"
  end
end
