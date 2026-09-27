defmodule HologramEcosystemTests.Ecto.TypesTest do
  use ExUnit.Case, async: true

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.DataFlow
  alias Hologram.Compiler.DataFlow.Rules.Ecto, as: EctoRules
  alias HologramEcosystemTests.Ecto.Post
  alias HologramEcosystemTests.Ecto.Tag
  alias HologramEcosystemTests.Ecto.Types.Stamp
  alias HologramEcosystemTests.Ecto.Types.Version

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

  defp shapes(type, flow), do: EctoRules.type_shapes(type, flow)

  # The type of a field of the post schema, as Ecto's reflection gives it.
  defp post_type(field), do: Post.__schema__(:type, field)

  test "primitive types", %{flow: flow} do
    assert shapes(:string, flow) == [:prim]
    assert shapes(:integer, flow) == [:prim]
    assert shapes(:binary_id, flow) == [:prim]
    assert shapes(:map, flow) == [:prim]
  end

  test "an enum is a primitive", %{flow: flow} do
    assert shapes(post_type(:status), flow) == [:prim]
  end

  test "calendar types are their structs", %{flow: flow} do
    assert shapes(:date, flow) == [@date]
    assert shapes(:utc_datetime, flow) == [@date_time]

    assert [{:struct, NaiveDateTime, %{calendar: [{:atom, Calendar.ISO}]}}] =
             shapes(:naive_datetime_usec, flow)

    assert [{:struct, Time, %{calendar: [{:atom, Calendar.ISO}]}}] = shapes(:time, flow)
  end

  test "the decimal type is its struct", %{flow: flow} do
    assert shapes(:decimal, flow) == [@decimal]
  end

  test "an array is a list of its items", %{flow: flow} do
    assert shapes({:array, :date}, flow) == [{:list, [@date]}]
  end

  test "a map of a type holds its values and primitive keys", %{flow: flow} do
    assert shapes({:map, :date}, flow) == [{:map, DataFlow.rest_fields([:prim, @date])}]
  end

  test "an embed of one is the embedded schema's record", %{flow: flow} do
    assert shapes(post_type(:main_tag), flow) == EctoRules.record_shapes(Tag, flow)
  end

  test "an embed of many is a list of the embedded schema's records", %{flow: flow} do
    assert shapes(post_type(:tags), flow) == [{:list, EctoRules.record_shapes(Tag, flow)}]
  end

  test "a type of the app holds what its load gives", %{flow: flow} do
    call = {:dyn, [{:atom, Stamp}], :load, 1, [[:prim]]}

    assert shapes(Stamp, flow) == [{:contents, [call]}]
  end

  test "a parameterized type of the app holds what its load gives", %{flow: flow} do
    call = {:dyn, [{:atom, Version}], :load, 3, [[:prim], [:prim], [:prim]]}

    assert shapes(post_type(:version), flow) == [{:contents, [call]}]
  end

  test "a parameterized type as Ecto before 3.12 writes it", %{flow: flow} do
    {:parameterized, {Version, params}} = post_type(:version)

    assert shapes({:parameterized, Version, params}, flow) ==
             shapes({:parameterized, {Version, params}}, flow)
  end

  test "is remembered in the rule cache", %{flow: flow} do
    shapes(:string, flow)

    assert PLT.get(flow.rule_cache, {EctoRules, :type, :string}) == {:ok, [:prim]}
  end
end
