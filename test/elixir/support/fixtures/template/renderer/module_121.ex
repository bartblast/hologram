defmodule Hologram.Test.Fixtures.Template.Renderer.Module121 do
  use Hologram.Component

  prop :items, :list
  prop :open?, :boolean

  @impl Component
  def template do
    ~HOLO"""
    {%for item <- @items}<li $ref={:item, item}></li>{/for}
    {%if @open?}<p $ref="toggle"></p>{%else}<div $ref="toggle"></div>{/if}
    """
  end
end
