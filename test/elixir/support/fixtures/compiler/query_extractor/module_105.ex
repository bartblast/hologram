# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module105 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module56
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :min_b, :integer

  derived :all_kinds, [Entity2], fn min_b -> Module56.by_kind(:all, min_b) end

  derived :bounded_large, [Entity2], fn min_b -> Module56.bounded(min_b, 20) end

  derived :bounded_small, [Entity2], fn min_b -> Module56.bounded(min_b, 5) end

  derived :inside_closure, [Entity2], fn min_b ->
    Enum.reduce([:open], Entity2, fn kind, query ->
      if kind == :open, do: filter(query, b >= ^min_b), else: query
    end)
  end

  derived :listed, [Entity2], fn min_b -> Module56.listed(min_b, :none) end

  derived :same_twice, [Entity2], fn min_b -> Module56.same(min_b, 1, 2) end

  derived :sized, [Entity2], fn min_b -> Module56.sized(min_b, 3) end

  derived :strict, [Entity2], fn min_b -> Module56.strict_or_loose(min_b, true) end

  derived :windowed, [Entity2], fn min_b -> Module56.windowed(min_b, 1, 5) end

  @impl Component
  def template do
    ~HOLO""
  end
end
