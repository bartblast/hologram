defmodule Hologram.Test.Fixtures.Template.Renderer.Module67 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Template.Renderer.Module68

  @impl Component
  def template do
    ~HOLO"""
    <Module68>
      {%if false}
        abc
      {/if}
    </Module68>
    """
  end
end
