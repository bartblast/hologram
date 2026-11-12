# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module106 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module13, as: Entity13
  alias Hologram.Test.Fixtures.Entity.Module26, as: Entity26
  alias Hologram.Test.Fixtures.Entity.Module3, as: Entity3

  prop :entity_type, :atom
  prop :relation, :atom

  derived :admitting_count, :integer, fn entity_type ->
    entity_type
    |> filter(a: true)
    |> count()
  end

  derived :entity_and_relation, [Entity13], fn entity_type, relation ->
    entity_type
    |> filter(title: "x")
    |> include(^relation)
  end

  derived :every_inverse, [Entity26], fn relation -> include(Entity26, ^relation) end

  derived :every_relationship, [Entity3], fn relation -> include(Entity3, ^relation) end

  derived :one_admitting_count, :integer, fn entity_type ->
    entity_type
    |> filter(d: 1)
    |> count()
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
