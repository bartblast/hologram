defmodule Hologram.Test.Fixtures.Template.Renderer.Module31 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Template.Renderer.Module32
  alias Hologram.Test.Fixtures.Template.Renderer.Module33

  @impl Component
  def template do
    ~HOLO"""
    31a,<Module32>31b,<Module33>31c,<slot />,31x,</Module33>31y,</Module32>31z
    """
  end
end
