defmodule HologramEcosystemTests.Ash.TypesTest do
  use ExUnit.Case, async: true

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.Rules.Ash, as: AshRules
  alias HologramEcosystemTests.Ash.Address
  alias HologramEcosystemTests.Ash.Types.Slug
  alias HologramEcosystemTests.Ash.Types.Status
  alias HologramEcosystemTests.Ash.Types.Window

  @date {:struct, Date,
         %{calendar: [{:atom, Calendar.ISO}], day: [:prim], month: [:prim], year: [:prim]}}

  @date_time {:struct, DateTime,
              %{
                calendar: [{:atom, Calendar.ISO}],
                day: [:prim],
                hour: [:prim],
                microsecond: [:prim],
                minute: [:prim],
                month: [:prim],
                second: [:prim],
                std_offset: [:prim],
                time_zone: [:prim],
                utc_offset: [:prim],
                year: [:prim],
                zone_abbr: [:prim]
              }}

  @decimal {:struct, Decimal, %{coef: [:prim], exp: [:prim], sign: [:prim]}}

  setup do
    [flow: DataFlow.start(PLT.start(), PLT.start())]
  end

  defp shapes(type, constraints \\ [], flow), do: AshRules.type_shapes(type, constraints, flow)

  test "Ash is available" do
    assert AshRules.available?()
  end

  test "primitive types", %{flow: flow} do
    assert shapes(:string, flow) == [:prim]
    assert shapes(:integer, flow) == [:prim]
    assert shapes(:uuid, flow) == [:prim]
    assert shapes(Ash.Type.Atom, flow) == [:prim]
  end

  test "an enum type is a primitive", %{flow: flow} do
    assert shapes(Status, flow) == [:prim]
  end

  test "calendar types are their structs", %{flow: flow} do
    assert shapes(:date, flow) == [@date]
    assert shapes(:utc_datetime, flow) == [@date_time]
  end

  test "the decimal type is its struct", %{flow: flow} do
    assert shapes(:decimal, flow) == [@decimal]
  end

  test "the money type is its struct, its amount a decimal", %{flow: flow} do
    fields = %{amount: [@decimal], currency: [:prim], format_options: [:prim]}

    assert shapes(:money, flow) == [{:struct, Money, fields}]
  end

  test "an array is a list of its items", %{flow: flow} do
    assert shapes({:array, :date}, flow) == [{:list, [@date]}]
  end

  test "a union holds its members' values", %{flow: flow} do
    constraints = [types: [day: [type: :date], text: [type: :string]]]

    assert shapes(Ash.Type.Union, constraints, flow) ==
             [{:struct, Ash.Union, %{type: [:prim], value: [:prim, @date]}}]
  end

  test "a map with fields holds each field's type", %{flow: flow} do
    constraints = [fields: [day: [type: :date], note: [type: :string]]]

    assert shapes(:map, constraints, flow) == [{:map, %{day: [@date], note: [:prim]}}]
  end

  test "a map without fields holds primitives", %{flow: flow} do
    assert shapes(:map, flow) == [{:map, DataFlow.rest_fields([:prim])}]
  end

  test "a keyword list holds its fields' types", %{flow: flow} do
    constraints = [fields: [day: [type: :date]]]

    assert shapes(:keyword, constraints, flow) == [{:list, [{:tuple, [[:prim], [@date]]}]}]
  end

  test "a tuple holds its fields' types in order", %{flow: flow} do
    constraints = [fields: [note: [type: :string], day: [type: :date]]]

    assert shapes(:tuple, constraints, flow) == [{:tuple, [[:prim], [@date]]}]
  end

  test "a struct type of a module is that struct", %{flow: flow} do
    constraints = [instance_of: Date, fields: [calendar: [type: :atom]]]

    assert [{:struct, Date, %{calendar: [:prim], day: [:prim]}}] =
             shapes(:struct, constraints, flow)
  end

  test "a new type is its subtype with its constraints", %{flow: flow} do
    assert shapes(Window, flow) == [{:map, %{from: [@date_time], to: [@date_time]}}]
  end

  test "an embedded resource is its record", %{flow: flow} do
    assert [{:struct, Address, %{street: _street}}] = shapes(Address, flow)
  end

  test "a type of the app holds what its cast gives", %{flow: flow} do
    call = {:dyn, [{:atom, Slug}], :cast_stored, 2, [[:prim], [:prim]]}

    assert shapes(Slug, flow) == [{:contents, [call]}]
  end

  test "is remembered in the rule cache", %{flow: flow} do
    shapes(:string, flow)

    assert PLT.get(flow.rule_cache, {AshRules, :type, :string, []}) == {:ok, [:prim]}
  end
end
