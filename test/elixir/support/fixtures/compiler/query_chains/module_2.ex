# credo:disable-for-this-file Credo.Check.Readability.Specs
# Some derived fields build a query on an if's value, the shape the build check reads.
# credo:disable-for-this-file Credo.Check.Refactor.PipeChainStart
defmodule Hologram.Test.Fixtures.Compiler.QueryChains.Module2 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Entity.Module15, as: Entity15
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :predicates, :list

  derived :rows, [Entity2], fn -> filter(Entity2, nonexistent == true) end

  derived :secrets, [Entity15], fn -> sort(Entity15, token) end

  derived :replaced_sort, [Entity15], fn ->
    Entity15
    |> sort(token)
    |> sort(label)
  end

  derived :counted_secrets, :integer, fn ->
    Entity15
    |> sort(token)
    |> count()
  end

  derived :sorted_again_after_cut, [Entity15], fn predicates ->
    Entity15
    |> sort(token)
    |> Stage.filter(predicates)
    |> sort(label)
  end

  derived :sorted_before_cut, [Entity15], fn predicates ->
    Entity15
    |> sort(token)
    |> Stage.filter(predicates)
  end

  derived :spread_secrets, [Entity15], fn ->
    label = "x"

    Entity15
    |> filter(label == ^label)
    |> sort(token)
  end

  derived :branch_secrets, [Entity15], fn predicates ->
    if predicates == [] do
      sort(Entity15, token)
    else
      Entity15
    end
  end

  derived :cond_secrets, [Entity15], fn predicates ->
    cond do
      predicates == [] ->
        label = "x"

        Entity15
        |> filter(label == ^label)
        |> sort(token)

      length(predicates) == 1 ->
        sort(Entity15, label)

      true ->
        Entity15
    end
  end

  derived :with_secrets, [Entity15], fn predicates ->
    # credo:disable-for-next-line Credo.Check.Readability.WithSingleClause
    with [] <- predicates do
      Entity15
    else
      _predicates -> sort(Entity15, token)
    end
  end

  derived :try_secrets, [Entity15], fn ->
    try do
      Entity15
    rescue
      _error -> sort(Entity15, token)
    end
  end

  derived :taken_branch_secrets, [Entity15], fn predicates ->
    if(predicates == [], do: sort(Entity15, token), else: Entity15)
    |> take(10)
  end

  derived :counted_branch, :integer, fn predicates ->
    if(predicates == [], do: sort(Entity15, token), else: Entity15)
    |> count()
  end

  derived :sorted_branch_again, [Entity15], fn predicates ->
    if(predicates == [], do: sort(Entity15, token), else: Entity15)
    |> sort(label)
  end

  # The condition's query is handed on, so a stage after it can still sort it again.
  derived :sorted_condition, [Entity15], fn ->
    case sort(Entity15, token) do
      query -> sort(query, label)
    end
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
