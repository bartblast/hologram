# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryChains.Module1 do
  use Hologram.DB

  alias Hologram.DB
  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Entity.Module1, as: Entity1
  alias Hologram.Test.Fixtures.Entity.Module15, as: Entity15
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  # string_sort/0 hands sort a spec its spec refuses on purpose, for the build check to refuse.
  @dialyzer {:nowarn_function, string_sort: 0}

  def valid(min_b) do
    Entity2
    |> filter(a == true and b >= ^min_b)
    |> sort(c)
    |> take(5)
  end

  def unknown_attribute do
    Entity2
    |> filter(a == true)
    |> sort(nonexistent)
  end

  def pinned_ordering(limit), do: filter(Entity2, a > ^limit)

  def pinned_beside_mistyped(value), do: filter(Entity2, b == ^value or c == 5)

  def pinned_predicates(predicates), do: Stage.filter(Entity2, predicates)

  def pinned_alternatives(alternatives), do: filter(Entity2, ^[a: true, or: alternatives])

  def pinned_any(condition), do: filter(Entity2, ^[a: true, any: condition])

  def pinned_all(condition), do: filter(Entity2, ^[a: true, all: condition])

  def pinned_none(condition), do: filter(Entity2, ^[a: true, none: condition])

  def literal_or, do: Stage.filter(Entity2, or: {:==, "x"})

  def operator_any, do: Stage.filter(Entity2, any: {:>=, 2})

  def through_variable(query), do: sort(query, nonexistent)

  def through_reduce(conditions) do
    Enum.reduce(conditions, Entity2, fn condition, query -> Stage.filter(query, [condition]) end)
  end

  def server_only, do: filter(Entity15, token == "x")

  def server_only_spread do
    Entity15
    |> sort(label)
    |> filter(token == "x")
    |> take(5)
  end

  def replaced_sort do
    Entity15
    |> sort(token)
    |> sort(label)
  end

  def sort_before_cut(predicates) do
    Entity15
    |> sort(token)
    |> Stage.filter(predicates)
    |> sort(label)
  end

  def pinned_sort(spec) do
    Entity2
    |> sort(^spec)
    |> filter(nonexistent == true)
  end

  def mistyped_range, do: filter(Entity2, c in 1..5)

  def pinned_operator_list(max), do: Stage.filter(Entity2, b: [{:>, 1}, {:<, max}])

  def pinned_operator(operator), do: Stage.filter(Entity2, b: [{:>, 1}, operator])

  def pinned_date, do: filter(Entity2, c == ^~D[2024-01-01])

  def string_sort, do: Stage.sort(Entity2, "c")

  def read_branch_secret(sorted?) do
    # credo:disable-for-next-line Credo.Check.Readability.NestedFunctionCalls
    DB.read(if sorted?, do: sort(Entity15, token), else: Entity15)
  end

  def read_sorted_secret do
    Entity15
    |> sort(token)
    |> DB.read()
  end

  def sorted_secret_in_fun, do: fn -> sort(Entity15, token) end

  def sorted_secret_handed_on do
    query = sort(Entity15, token)
    sort(query, label)
  end

  def dead_cut(predicates), do: Stage.filter(Entity1, predicates)

  def through_helper, do: sort(entity_type(), nonexistent)

  defp entity_type, do: Entity2

  def dead, do: filter(Entity1, id != nil)

  def trusted, do: trust(filter(Entity15, label == "x"))
end
