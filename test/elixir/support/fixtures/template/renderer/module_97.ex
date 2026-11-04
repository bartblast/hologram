# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module97 do
  use Hologram.Component

  prop :products, :list

  @impl Component
  def template do
    ~HOLO"""
    <select>{%for %{category: category} <- @products, uniq: true}<option>{category}</option>{/for}</select>
    """
  end
end
