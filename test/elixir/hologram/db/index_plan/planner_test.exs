defmodule Hologram.DB.IndexPlan.PlannerTest do
  # async: false - the indexes each test builds lock their table until the sandbox rolls back.
  use Hologram.Test.DatabaseCase, async: false
  use Hologram.DB

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.DDL
  alias Hologram.DB.IndexPlan
  alias Hologram.DB.Introspection
  alias Hologram.DB.QueryCompiler
  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module52

  # What Postgres plans the given query's statement with: the plan's indexes built, inside the
  # sandbox's transaction, and sequential scans priced out, so that an index serving the statement
  # is the one the plan reads. The tables are empty, so the planner would scan them otherwise.
  # Unnamed, so the statement is planned with its values, as the runner's are.
  defp explain(query, policy \\ nil, settings \\ []) do
    mapping = DB.mapping()
    term = Stage.normalize(query)

    plan =
      term
      |> IndexPlan.needs(mapping, policy)
      |> IndexPlan.select(mapping)

    build_indexes(plan)

    Enum.each(["enable_seqscan = off" | settings], fn setting ->
      {:ok, _result} = Connection.query("SET LOCAL #{setting}")
    end)

    compiled = QueryCompiler.compile(term, mapping, policy)
    values = Enum.map(compiled.params, fn {:value, value} -> value end)

    {:ok, %{rows: [[[%{"Plan" => root}]]]}} =
      Connection.query("EXPLAIN (FORMAT JSON) " <> compiled.sql, values)

    {plan_index_names(plan), nodes(root)}
  end

  # Builds the plan's indexes the schema doesn't hold already, as a framework need's.
  defp build_indexes(plan) do
    schema = Introspection.schema()

    for {table, indexes} <- plan,
        {name, definition} <- indexes,
        not Map.has_key?(schema.tables[table].indexes, name) do
      op = Map.merge(definition, %{op: :create_index, table: table, index: name})

      op
      |> DDL.statements()
      |> Enum.each(&({:ok, _result} = Connection.query(&1)))
    end
  end

  defp plan_index_names(plan) do
    plan
    |> Enum.flat_map(fn {_table, indexes} -> Map.keys(indexes) end)
    |> Enum.sort()
  end

  defp nodes(node), do: [node | Enum.flat_map(node["Plans"] || [], &nodes/1)]

  defp node_types(nodes), do: Enum.map(nodes, & &1["Node Type"])

  defp read_index_names(nodes) do
    nodes
    |> Enum.map(& &1["Index Name"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp rule(entity_type, predicates) do
    %{predicates: Stage.predicate_triples!(entity_type, predicates), to: nil, via: nil}
  end

  test "reads the indexes of two read rules in one BitmapOr" do
    policy = %{anonymous?: false, rules: [rule(Module2, a: true), rule(Module2, c: "x")]}

    {index_names, nodes} = explain(Module2, policy)

    assert length(index_names) == 2
    assert read_index_names(nodes) == index_names
    assert "BitmapOr" in node_types(nodes)
  end

  test "reads a string equality through the sort key's index" do
    {[index_name], nodes} = explain(filter(Module2, c == "x"))

    assert read_index_names(nodes) == [index_name]
  end

  test "reads a string range through the sort key's index" do
    {[index_name], nodes} = explain(filter(Module2, c >= "m"))

    assert read_index_names(nodes) == [index_name]
  end

  # Sorting priced out too: a plan that sorts anyway is one no index gives the order of.
  test "reads a bounded sort in the index's order, sorting nothing" do
    query =
      Module52
      |> filter(slug == "x")
      |> take(5)

    {[index_name], nodes} = explain(query, nil, ["enable_sort = off"])

    assert read_index_names(nodes) == [index_name]
    refute "Sort" in node_types(nodes)
  end

  test "reads the related rows of an inverse level through the plan's index" do
    query = filter(Module26, none(m <- messages, m.body == "y" and m.position > 1))

    {[index_name], nodes} = explain(query)

    assert index_name in read_index_names(nodes)
  end
end
