# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.Module43 do
  use Hologram.Component

  prop :items, :list

  def template do
    ~HOLO"""
    {%for item <- @items}<li $ref={:item, item.id}></li>{/for}
    """
  end
end
