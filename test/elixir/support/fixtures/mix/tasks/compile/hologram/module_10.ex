defmodule Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module10 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    {%for item <- [1, 2]}<li $ref={:item, item}></li>{/for}
    """
  end
end
