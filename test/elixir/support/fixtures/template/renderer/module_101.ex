# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module101 do
  use Hologram.Component
  use Hologram.Query

  alias Hologram.Test.Fixtures.Entity.Module2

  prop :a, :boolean
  prop :total, :integer, from_query: &total_query/1

  @impl Component
  def template do
    ~HOLO"""
    total = {@total}
    """
  end

  defp total_query(a) do
    Module2
    |> filter(a: a)
    |> count()
  end
end
