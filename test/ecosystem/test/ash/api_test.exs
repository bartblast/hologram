defmodule HologramEcosystemTests.Ash.ApiTest do
  use ExUnit.Case, async: true

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.Rules.Ash, as: AshRules
  alias HologramEcosystemTests.Ash.ApiCalls
  alias HologramEcosystemTests.Ash.Domain
  alias HologramEcosystemTests.Ash.Item
  alias HologramEcosystemTests.Ash.Note

  setup do
    module_info_plt =
      PLT.put(PLT.start(), [
        {ApiCalls, %{exception?: false}},
        {Domain, %{exception?: false}},
        {Item, %{exception?: false}},
        {Note, %{exception?: false}}
      ])

    [flow: DataFlow.start(PLT.start(), module_info_plt)]
  end

  defp summary(function, arity, flow) do
    {ApiCalls, function, arity}
    |> DataFlow.summary(flow)
    |> DataFlow.to_tree(flow)
  end

  # The structs a list in the tree holds, at its top.
  defp listed(tree),
    do: for({:list, elements} <- tree, {:struct, module, _fields} <- elements, do: module)

  test "a read of a query built from a resource gives that resource's records", %{flow: flow} do
    assert listed(summary(:filtered, 0, flow)) == [Item]
  end

  test "a read's options do not bring their records in", %{flow: flow} do
    assert listed(summary(:with_actor, 0, flow)) == [Item]
  end

  test "a create of a changeset built from a resource gives its record", %{flow: flow} do
    tree = summary(:created, 0, flow)

    assert Enum.any?(tree, &match?({:struct, Item, _fields}, &1))
  end

  test "a get gives {:ok, record or nil} or {:error, error}", %{flow: flow} do
    tree = summary(:fetched, 1, flow)

    assert [ok] = for({:tuple, [[{:atom, :ok}], ok]} <- tree, do: ok)
    assert Enum.any?(ok, &match?({:struct, Item, _fields}, &1))
    assert [errors] = for({:tuple, [[{:atom, :error}], errors]} <- tree, do: errors)
    assert Enum.any?(errors, &match?({:struct, Ash.Error.Invalid, _fields}, &1))
  end

  test "a load gives the records it is given", %{flow: flow} do
    tree = summary(:loaded, 1, flow)

    assert Enum.any?(tree, &match?({:struct, Item, _fields}, &1))
    assert listed(tree) == [Item]
  end

  test "an update of a record not known yet waits for it", %{flow: flow} do
    assert :updated
           |> summary(1, flow)
           |> Enum.any?(&match?({:rule, AshRules, :records, _args}, &1))
  end

  test "an update of a record gives its resource's record", %{flow: flow} do
    tree = summary(:updates_fetched, 1, flow)

    assert Enum.any?(tree, &match?({:struct, Item, _fields}, &1))
    refute Enum.any?(tree, &match?({:rule, _rules_module, _name, _args}, &1))
  end

  test "a count is a primitive", %{flow: flow} do
    assert summary(:counted, 0, flow) == [:prim]
  end

  test "a query's function gives the query, holding its resource", %{flow: flow} do
    assert [{:struct, Ash.Query, %{{:rest} => rest}}] =
             AshRules.resolve(:subject, [[Ash.Query], [Item]], flow)

    assert {:atom, Item} in rest
  end

  test "a call naming no resource gives every resource's types", %{flow: flow} do
    assert [{:bag, leaves}] = AshRules.resolve(:records, [[]], flow)
    assert {:struct, Item, %{}} in leaves
    assert {:struct, Note, %{}} in leaves
  end
end
