# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module78 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module79
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :entity_type, :atom
  prop :items, :list
  prop :only_ripe, :boolean
  prop :row, :any
  prop :user, :any
  prop :wanted, :boolean

  derived :branch_entity, [Entity2], fn only_ripe ->
    if only_ripe, do: Entity2, else: Entity2
  end

  derived :by_wanted, [Entity2], fn wanted -> filter(Entity2, a == ^wanted) end

  derived :can_read, :boolean, fn user, row -> can?(user, :read, row) end

  derived :chosen_entity, [Entity2], fn entity_type -> filter(entity_type, a == true) end

  derived :entity_label, :string, fn -> inspect(Module79.entity_type()) end

  derived :every_row, [Entity2], fn -> Entity2 end

  derived :labels, :list, fn items ->
    {first, _rest} = List.pop_at(items, 0)

    for item <- [first | items], do: "#{item}!"
  end

  derived :raising, :string, fn -> raise "computed at runtime only" end

  derived :ripe, [Entity2], fn -> filter(Entity2, a == true) end

  derived :ripe_or_all, [Entity2], fn only_ripe ->
    if only_ripe, do: filter(Entity2, a == true), else: Entity2
  end

  derived :sorted_entity, [Entity2], fn entity_type -> sort(entity_type, id) end

  derived :through_builder, [Entity2], fn wanted -> Module79.wanted(wanted) end

  @impl Component
  def template do
    ~HOLO""
  end
end
