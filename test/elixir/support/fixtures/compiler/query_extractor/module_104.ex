# credo:disable-for-this-file Credo.Check.Readability.Specs
# credo:disable-for-this-file Credo.Check.Refactor.CondStatements
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module104 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module19
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module56
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :kind, :atom
  prop :limit, :integer
  prop :min_b, :integer
  prop :status, :string

  derived :by_status, [Entity2], fn status ->
    case status do
      :any -> Entity2
      _other -> filter(Entity2, c: ^status)
    end
  end

  derived :cond_bound, [Entity2], fn min_b ->
    cond do
      min_b -> filter(Entity2, b >= ^min_b)
      true -> filter(Entity2, a: true)
    end
  end

  derived :guard_limit, [Entity2], fn limit, min_b -> Module56.bounded(min_b, limit) end

  derived :helper_clauses, [Entity2], fn min_b -> Module19.bounded_query(min_b) end

  derived :if_bound, [Entity2], fn min_b ->
    if min_b do
      filter(Entity2, b >= ^min_b)
    else
      filter(Entity2, a: true)
    end
  end

  derived :mixed, [Entity2], fn min_b -> Module56.mixed(min_b, :always) end

  derived :paired, [Entity2], fn kind, min_b -> Module56.paired(min_b, kind) end

  @impl Component
  def template do
    ~HOLO""
  end
end
