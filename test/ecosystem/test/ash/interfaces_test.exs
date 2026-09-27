defmodule HologramEcosystemTests.Ash.InterfacesTest do
  use ExUnit.Case, async: true

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.Rules.Ash, as: AshRules
  alias HologramEcosystemTests.Ash.Domain
  alias HologramEcosystemTests.Ash.Item
  alias HologramEcosystemTests.Ash.Note
  alias HologramEcosystemTests.Ash.Reader

  # The rules find the interfaces among the compile's modules, and Ash's exceptions by the module
  # info's flag.
  setup do
    module_info_plt =
      PLT.put(PLT.start(), [
        {Ash.Error.Invalid.NoSuchInput, %{exception?: true}},
        {Domain, %{exception?: false}},
        {Item, %{exception?: false}},
        {Note, %{exception?: false}},
        {Reader, %{exception?: false}}
      ])

    [flow: DataFlow.start(PLT.start(), module_info_plt)]
  end

  defp answer(function, arity, flow, module \\ Item),
    do: AshRules.summary({module, function, arity}, flow)

  defp record(flow), do: AshRules.record_shapes(Item, flow)

  # Whether the answer holds every shape of the record.
  defp holds_record?(answer, flow) do
    flow
    |> record()
    |> Enum.all?(&(&1 in answer))
  end

  defp ok_tuple(answer) do
    for {:tuple, [[{:atom, :ok}], tree]} <- answer, do: tree
  end

  test "a read by id gives the record or nil", %{flow: flow} do
    assert answer(:get!, 1, flow) == Enum.sort([:prim | record(flow)])
  end

  test "the form that does not raise wraps it in {:ok, ...} or {:error, error}", %{flow: flow} do
    answer = answer(:get, 1, flow)

    assert ok_tuple(answer) == [Enum.sort([:prim | record(flow)])]

    assert [errors] = for({:tuple, [[{:atom, :error}], errors]} <- answer, do: errors)
    assert Enum.any?(errors, &match?({:struct, Ash.Error.Invalid, _fields}, &1))
  end

  test "an error holds Ash's exceptions", %{flow: flow} do
    [errors] = for {:tuple, [[{:atom, :error}], errors]} <- answer(:get, 1, flow), do: errors

    [{:struct, Ash.Error.Invalid, fields}] =
      Enum.filter(errors, &match?({:struct, Ash.Error.Invalid, _fields}, &1))

    assert [{:list, [{:struct, Ash.Error.Invalid.NoSuchInput, _fields}]}] = fields.errors
  end

  test "an error's changeset holds the resource and a bag of the types its records hold", %{
    flow: flow
  } do
    [errors] = for {:tuple, [[{:atom, :error}], errors]} <- answer(:get, 1, flow), do: errors

    [{:struct, Ash.Error.Invalid, fields}] =
      Enum.filter(errors, &match?({:struct, Ash.Error.Invalid, _fields}, &1))

    [{:struct, Ash.Changeset, %{{:rest} => rest}}] =
      Enum.filter(fields.changeset, &match?({:struct, Ash.Changeset, _fields}, &1))

    assert {:atom, Item} in rest
    refute Enum.any?(rest, &match?({:struct, Item, _fields}, &1))
    assert [{:bag, leaves}] = Enum.filter(rest, &match?({:bag, _leaves}, &1))

    for module <- [Ash.NotLoaded, Ecto.Schema.Metadata, Item, Money, Note] do
      assert {:struct, module, %{}} in leaves
    end
  end

  # Ash's default read action paginates when asked to.
  test "a read gives a list of records or a page of them", %{flow: flow} do
    answer = answer(:list!, 0, flow)

    assert {:list, record(flow)} in answer

    assert Enum.any?(
             answer,
             &match?({:struct, Ash.Page.Offset, %{results: [{:list, _records}]}}, &1)
           )

    assert Enum.any?(
             answer,
             &match?({:struct, Ash.Page.Keyset, %{results: [{:list, _records}]}}, &1)
           )
  end

  test "a create or an update gives the record, with its notifications when asked", %{
    flow: flow
  } do
    for function <- [:create!, :update!] do
      answer = answer(function, 1, flow)

      assert holds_record?(answer, flow)
      assert Enum.any?(answer, &match?({:tuple, [_record, [{:list, _notifications}]]}, &1))
    end
  end

  test "a destroy gives :ok or the record", %{flow: flow} do
    answer = answer(:archive!, 1, flow)

    assert {:atom, :ok} in answer
    assert holds_record?(answer, flow)
  end

  test "a generic action gives its return type", %{flow: flow} do
    assert answer(:summarize!, 1, flow) == [:prim]
  end

  test "a calculation interface gives the calculation's type", %{flow: flow} do
    assert answer(:greeting!, 2, flow) == [:prim]
    assert ok_tuple(answer(:greeting, 2, flow)) == [[:prim]]
  end

  test "can_... gives whether the actor can, can_...? a boolean", %{flow: flow} do
    assert answer(:can_create?, 2, flow) == [:prim]
    assert [[:prim]] = ok_tuple(answer(:can_create, 2, flow))
  end

  test "changeset_to_... and query_to_... give the subject, naming the resource", %{flow: flow} do
    assert [{:struct, Ash.Changeset, %{{:rest} => rest}}] = answer(:changeset_to_create, 1, flow)
    assert {:atom, Item} in rest

    assert [{:struct, Ash.Query, %{{:rest} => _rest}}] = answer(:query_to_list, 0, flow)
  end

  test "a namespaced interface's functions are on the namespace module", %{flow: flow} do
    assert answer(:list_all!, 0, flow, Item.Admin) == answer(:list!, 0, flow)
    assert answer(:list_all!, 0, flow) == nil
  end

  test "a domain's interface gives the resource's records", %{flow: flow} do
    assert answer(:get_item!, 1, flow, Domain) == Enum.sort([:prim | record(flow)])
  end

  test "a function no interface generates has no answer", %{flow: flow} do
    assert answer(:unknown, 0, flow) == nil
  end

  test "a field of a record from an interface holds that field's types only", %{flow: flow} do
    summary = DataFlow.summary({Reader, :title, 1}, flow)

    refute Money in DataFlow.types(summary, flow).structs
    assert :prim in DataFlow.to_tree(summary, flow)
  end
end
