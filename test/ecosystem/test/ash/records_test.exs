defmodule HologramEcosystemTests.Ash.RecordsTest do
  use ExUnit.Case, async: true

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.Rules.Ash, as: AshRules
  alias HologramEcosystemTests.Ash.Item
  alias HologramEcosystemTests.Ash.Note

  setup do
    [flow: DataFlow.start(PLT.start(), PLT.start())]
  end

  defp fields(resource, flow) do
    [{:struct, ^resource, fields}] = AshRules.record_shapes(resource, flow)
    fields
  end

  defp not_loaded(resource) do
    {:struct, Ash.NotLoaded, %{field: [:prim], resource: [{:atom, resource}], type: [:prim]}}
  end

  test "an attribute holds its type, nil or a forbidden field holding its original value", %{
    flow: flow
  } do
    forbidden =
      {:struct, Ash.ForbiddenField, %{field: [:prim], original_value: [:prim], type: [:prim]}}

    assert fields(Item, flow).title == [:prim, forbidden]
  end

  test "an attribute of a struct type holds the struct", %{flow: flow} do
    assert [{:struct, Money, %{amount: [{:struct, Decimal, _decimal}]}} | _rest] =
             Enum.filter(fields(Item, flow).price, &match?({:struct, Money, _fields}, &1))

    assert Enum.any?(fields(Item, flow).available_on, &match?({:struct, Date, _fields}, &1))
  end

  test "an attribute of a new type holds its subtype's fields", %{flow: flow} do
    assert Enum.any?(fields(Item, flow).window, &match?({:map, %{from: _from, to: _to}}, &1))
  end

  test "a calculation or an aggregate holds its type, nil or not loaded", %{flow: flow} do
    assert fields(Item, flow).label == [:prim, not_loaded(Item)]
    assert fields(Item, flow).note_count == [:prim, not_loaded(Item)]
  end

  test "a to-many relationship holds a list of the related records, nil or not loaded", %{
    flow: flow
  } do
    notes = fields(Item, flow).notes

    assert :prim in notes
    assert not_loaded(Item) in notes

    assert [{:list, [{:struct, Note, note_fields}]}] =
             Enum.filter(notes, &match?({:list, _records}, &1))

    assert note_fields.text == fields(Note, flow).text
  end

  test "a relationship past the depth is a bag of the types every reachable record holds", %{
    flow: flow
  } do
    [{:list, [{:struct, Note, note_fields}]}] =
      Enum.filter(fields(Item, flow).notes, &match?({:list, _records}, &1))

    assert [{:bag, leaves}] = Enum.filter(note_fields.item, &match?({:bag, _leaves}, &1))
    assert {:struct, Item, %{}} in leaves
    assert {:struct, Note, %{}} in leaves
    assert {:struct, Money, %{}} in leaves
    assert {:struct, Decimal, %{}} in leaves
  end

  test "Ash's own fields", %{flow: flow} do
    fields = fields(Item, flow)

    assert [{:struct, Ecto.Schema.Metadata, %{schema: [{:atom, Item}]}}] = fields.__meta__
    assert fields.__order__ == [:prim]
    assert fields.__lateral_join_source__ == [:prim]
    assert [{:map, %{{:rest} => [:prim]}}] = fields.__metadata__
    assert [{:map, %{{:rest} => loaded}}] = fields.calculations
    assert not_loaded(Item) in loaded
  end

  test "is remembered in the rule cache", %{flow: flow} do
    record = AshRules.record_shapes(Item, flow)

    assert PLT.get(flow.rule_cache, {AshRules, :record, Item, 0}) == {:ok, record}
  end
end
