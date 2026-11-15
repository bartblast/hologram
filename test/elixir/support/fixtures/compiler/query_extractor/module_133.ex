# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module133 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module1, as: Entity1
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Entity.Module3, as: Entity3

  prop :through_path, :boolean

  derived :either_count, :integer, fn through_path ->
    if through_path do
      Entity3
      |> filter(b.a == true)
      |> count()
    else
      count(Entity1)
    end
  end

  derived :ripe_count, :integer, fn ->
    Entity2
    |> filter(a == true)
    |> count()
  end

  derived :rows, [Entity2], fn -> Entity2 end

  @impl Component
  def template do
    ~HOLO""
  end
end
