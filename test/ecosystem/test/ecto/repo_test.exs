defmodule HologramEcosystemTests.Ecto.RepoTest do
  use ExUnit.Case, async: true

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.Rules.Ecto, as: EctoRules
  alias HologramEcosystemTests.Ash.Item
  alias HologramEcosystemTests.Ash.Note
  alias HologramEcosystemTests.Ecto.Comment
  alias HologramEcosystemTests.Ecto.Post
  alias HologramEcosystemTests.Ecto.Repo
  alias HologramEcosystemTests.Ecto.RepoCalls
  alias HologramEcosystemTests.Ecto.Tag

  # The fallback of every schema's records reads the schemas from the module info's flag.
  setup do
    module_info_plt =
      PLT.put(PLT.start(), [
        {Comment, %{ecto_schema?: true, exception?: false}},
        {Item, %{ecto_schema?: true, exception?: false}},
        {Note, %{ecto_schema?: true, exception?: false}},
        {Post, %{ecto_schema?: true, exception?: false}},
        {RepoCalls, %{exception?: false}},
        {Tag, %{ecto_schema?: true, exception?: false}}
      ])

    [flow: DataFlow.start(PLT.start(), module_info_plt)]
  end

  defp summary(function, arity, flow) do
    {RepoCalls, function, arity}
    |> DataFlow.summary(flow)
    |> DataFlow.to_tree(flow)
  end

  # The fields of the module's record among the shapes, which must hold one.
  defp record_fields(shapes, module) do
    {:struct, ^module, fields} = List.keyfind(shapes, module, 1)
    fields
  end

  # The shapes the value in the tuple of the given tag holds.
  defp tagged(tree, tag) do
    [{:tuple, [_tag, value]}] =
      Enum.filter(tree, &match?({:tuple, [[{:atom, ^tag}], _value]}, &1))

    value
  end

  defp struct?(shapes, module), do: Enum.any?(shapes, &match?({:struct, ^module, _fields}, &1))

  test "a read of many gives a list of the schema's records", %{flow: flow} do
    assert [{:list, [{:struct, Post, _fields}]}] = summary(:all, 0, flow)
    assert [{:list, [{:struct, Post, _fields}]}] = summary(:all_by, 0, flow)
  end

  test "a read of one gives the schema's record or nil", %{flow: flow} do
    assert [:prim, {:struct, Post, _fields}] = summary(:fetched, 1, flow)
  end

  test "a read of one that raises gives the schema's record", %{flow: flow} do
    assert [{:struct, Post, _fields}] = summary(:fetched!, 1, flow)
  end

  test "a record's fields hold what the schema's types give, a custom type's load made", %{
    flow: flow
  } do
    fields = record_fields(summary(:fetched!, 1, flow), Post)
    record_fields = record_fields(EctoRules.record_shapes(Post, flow), Post)

    assert Map.keys(fields) == Map.keys(record_fields)
    assert struct?(fields.published_on, Date)
    assert struct?(fields.stamp, Date)
    assert struct?(fields.version, Version)
  end

  test "a write gives the record or a changeset holding it", %{flow: flow} do
    tree = summary(:inserted, 0, flow)

    assert [{:struct, Post, _fields}] = tagged(tree, :ok)
    assert struct?(record_fields(tagged(tree, :error), Ecto.Changeset).data, Post)
  end

  test "a write that raises gives the record", %{flow: flow} do
    assert [{:struct, Post, _fields}] = summary(:inserted!, 0, flow)
  end

  test "a write of a changeset gives the record of the changeset's data", %{flow: flow} do
    assert struct?(tagged(summary(:updated, 1, flow), :ok), Post)
  end

  test "a preload gives what it is given, with the schema's record", %{flow: flow} do
    assert struct?(summary(:preloaded, 1, flow), Post)
  end

  test "a call on a value not known yet waits for it, with no fallback", %{flow: flow} do
    tree = summary(:reloaded, 1, flow)

    assert Enum.any?(tree, &match?({:rule, EctoRules, :records, _args}, &1))
    refute Enum.any?(tree, &match?({:bag, _leaves}, &1))
  end

  test "a read of an Ash resource gives Ash's record of it", %{flow: flow} do
    fields = record_fields(summary(:fetched_resource, 1, flow), Item)

    assert struct?(fields.price, Money)
    assert struct?(fields.stamp, Date)
  end

  test "a read naming no schema gives every schema's types, Ash's resources' included", %{
    flow: flow
  } do
    assert [{:list, [{:bag, leaves}]}] = summary(:from_source, 0, flow)

    for module <- [Comment, Item, Money, Note, Post, Tag] do
      assert {:struct, module, %{}} in leaves
    end
  end

  test "a repo's function the rules do not know, and any other module's, have no answer", %{
    flow: flow
  } do
    assert EctoRules.summary({Repo, :transaction, 2}, flow) == nil
    assert EctoRules.summary({RepoCalls, :all, 0}, flow) == nil
  end
end
