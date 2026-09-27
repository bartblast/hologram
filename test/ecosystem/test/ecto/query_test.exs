defmodule HologramEcosystemTests.Ecto.QueryTest do
  use ExUnit.Case, async: true

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.Rules.Ecto, as: EctoRules
  alias HologramEcosystemTests.Ash.Item
  alias HologramEcosystemTests.Ash.Note
  alias HologramEcosystemTests.Ecto.Comment
  alias HologramEcosystemTests.Ecto.Post
  alias HologramEcosystemTests.Ecto.QueryCalls
  alias HologramEcosystemTests.Ecto.Tag

  # The fallback of every schema's records reads the schemas from the module info's flag.
  setup do
    module_info_plt =
      PLT.put(PLT.start(), [
        {Comment, %{ecto_schema?: true, exception?: false}},
        {Item, %{ecto_schema?: true, exception?: false}},
        {Note, %{ecto_schema?: true, exception?: false}},
        {Post, %{ecto_schema?: true, exception?: false}},
        {QueryCalls, %{exception?: false}},
        {Tag, %{ecto_schema?: true, exception?: false}}
      ])

    [flow: DataFlow.start(PLT.start(), module_info_plt)]
  end

  defp summary(function, arity, flow) do
    {QueryCalls, function, arity}
    |> DataFlow.summary(flow)
    |> DataFlow.to_tree(flow)
  end

  # The struct modules among the shapes.
  defp modules(shapes), do: for({:struct, module, _fields} <- shapes, do: module)

  # The records a list among the shapes holds.
  defp listed(shapes), do: for({:list, records} <- shapes, record <- records, do: record)

  # What a changeset among the shapes holds in its fields.
  defp changeset_values(shapes) do
    [{:struct, Ecto.Changeset, fields}] =
      Enum.filter(shapes, &match?({:struct, Ecto.Changeset, _fields}, &1))

    fields
    |> Map.values()
    |> Enum.concat()
  end

  test "a query Ecto's macros build at compile time names its schema", %{flow: flow} do
    records = listed(summary(:by_literal, 0, flow))

    assert Post in modules(records)
    refute Enum.any?(records, &match?({:bag, _leaves}, &1))
  end

  test "a query built by a pipeline of Ecto's macros names its schema", %{flow: flow} do
    assert modules(listed(summary(:by_pipeline, 0, flow))) == [Post]
  end

  test "a subquery names its query's schema", %{flow: flow} do
    records = listed(summary(:by_subquery, 0, flow))

    assert Post in modules(records)
    refute Enum.any?(records, &match?({:bag, _leaves}, &1))
  end

  test "a query joining another schema names both", %{flow: flow} do
    modules = modules(listed(summary(:joined, 0, flow)))

    assert Post in modules
    assert Comment in modules
  end

  test "a changeset holds its schema's record, whose fields hold what their types give", %{
    flow: flow
  } do
    values = changeset_values(summary(:built, 1, flow))

    assert [{:struct, Post, fields}] = Enum.filter(values, &match?({:struct, Post, _fields}, &1))
    assert Enum.any?(fields.stamp, &match?({:struct, Date, _fields}, &1))
  end

  test "a repo write of a changeset gives its schema's record", %{flow: flow} do
    tree = summary(:inserted, 1, flow)

    assert [{:tuple, [[{:atom, :ok}], records]}] =
             Enum.filter(tree, &match?({:tuple, [[{:atom, :ok}], _value]}, &1))

    assert Post in modules(records)
  end

  test "applying a changeset's changes gives its schema's record", %{flow: flow} do
    assert Post in modules(summary(:applied, 1, flow))
  end

  test "a schemaless changeset holds the changeset it is given, and no schema's records", %{
    flow: flow
  } do
    values = changeset_values(summary(:schemaless, 1, flow))

    assert modules(values) == [Ecto.Changeset]
    refute Enum.any?(values, &match?({:bag, _leaves}, &1))
  end

  test "the functions of Ecto.Query give their structs", %{flow: flow} do
    assert [{:struct, Ecto.SubQuery, _fields}] =
             EctoRules.summary({Ecto.Query, :subquery, 1}, flow)

    assert [{:struct, Ecto.Query, _fields}] =
             EctoRules.summary({Ecto.Query.Builder.Filter, :apply, 3}, flow)

    assert EctoRules.summary({Ecto.Query, :has_named_binding?, 2}, flow) == [:prim]
  end

  test "a function of Ecto.Changeset giving no changeset is followed", %{flow: flow} do
    assert EctoRules.summary({Ecto.Changeset, :get_field, 3}, flow) == nil
  end
end
