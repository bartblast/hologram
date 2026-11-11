# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module174 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2

  prop :a, :boolean

  derived :total, :integer, fn a ->
    Module2
    |> filter(a == ^a)
    |> count()
  end

  @impl Component
  def template do
    ~HOLO"""
    total = {@total}
    """
  end
end
