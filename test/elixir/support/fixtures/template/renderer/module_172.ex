# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Template.Renderer.Module172 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module8, as: PolicyModule8

  derived :chained, [PolicyModule8], fn -> sort(PolicyModule8, created_at) end

  derived :entities, [PolicyModule1], fn ->
    PolicyModule1
    |> filter(public == true)
    |> sort(priority)
  end

  @impl Component
  def template do
    ~HOLO"""
    parents = {Enum.map_join(@entities, ",", &inspect(&1.parent))}
    """
  end
end
