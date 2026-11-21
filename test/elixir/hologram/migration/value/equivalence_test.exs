defmodule Hologram.Migration.Value.EquivalenceTest do
  # SQL and Elixir have to give the same value for every row: a fill runs one, and a write queued
  # from before the migration runs the other. Each case computes a backfill both ways over the
  # same rows, on a real database.
  #
  # async: false - every module of the scratch tier opens raw sessions beside its scratch
  # connection.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Migrator

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Migration.Value
  alias Hologram.Migration.Value.Evaluator
  alias Hologram.Migration.Value.Loader
  alias Hologram.Migration.Value.SQL

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  @attributes [
    active: {:boolean, []},
    at: {:datetime, []},
    budget: {:float, []},
    day: {:date, []},
    destination: {:string, []},
    external: {:uuid, []},
    first: {:string, []},
    kind: {:enum, [values: [:live, :old, :draft]]},
    last: {:string, []},
    seats: {:integer, []},
    state: {:enum, [values: [:draft, :live]]},
    starts: {:time, []}
  ]

  @ops [
         %{op: :create_entity, entity: MyApp.User, line: 1},
         %{
           op: :add_attribute,
           entity: MyApp.User,
           name: :name,
           type: :string,
           opts: [optional: true],
           line: 2
         },
         %{op: :create_entity, entity: MyApp.Trip, line: 3}
       ] ++
         Enum.map(@attributes, fn {name, {type, opts}} ->
           %{
             op: :add_attribute,
             entity: MyApp.Trip,
             name: name,
             type: type,
             opts: [{:optional, true} | opts],
             line: 4
           }
         end) ++
         [
           %{
             op: :add_relationship,
             entity: MyApp.Trip,
             name: :owner,
             type: MyApp.User,
             opts: [optional: true],
             line: 5
           },
           %{
             op: :add_relationship,
             entity: MyApp.Trip,
             name: :parent,
             type: MyApp.Trip,
             opts: [optional: true],
             line: 6
           }
         ]

  @texts [
    nil,
    "",
    "Porto, Portugal",
    ", Porto",
    "Porto, ",
    "a, , b",
    ", ",
    "no separator",
    "aaa",
    "aaaa",
    "100% sure",
    "a.b.c",
    "żółć, gęś",
    "日本語, テキスト",
    "é, x"
  ]

  defp assert_same(term, target) do
    model = Model.fold(Model.empty(), @ops)
    mapping = Mapper.derive_from_model!(model)
    resolved = Value.resolve!(%Value{term: term}, model, MyApp.Trip, target)
    {fragment, params} = SQL.render(resolved, MyApp.Trip, mapping, target)

    statement = """
    SELECT "$r0"."id", #{fragment}
    FROM "hologram_data"."my_app_trip" AS "$r0"
    ORDER BY "$r0"."id"
    """

    {:ok, %{rows: rows}} = Connection.query(statement, params)

    from_sql =
      Map.new(rows, fn [id, value] ->
        {Codec.decode(id, :uuid), decode(value, resolved.type)}
      end)

    ids = Map.keys(from_sql)
    reads = Evaluator.reads(resolved.term)
    loaded = Loader.load(reads, MyApp.Trip, ids, mapping)

    assert length(loaded) == length(ids)

    for row <- loaded do
      assert {inspect(term), row.id, Evaluator.evaluate(resolved.term, row)} ==
               {inspect(term), row.id, from_sql[row.id]}
    end
  end

  defp attribute_target(type, opts \\ []) do
    %{kind: :attribute, line: 9, name: :value, opts: opts, type: type}
  end

  defp decode(nil, _type), do: nil

  defp decode(value, {:enum, _owner, _name, _values}), do: Codec.decode(value, :enum)

  defp decode(value, {:reference, _target}), do: Codec.decode(value, :uuid)

  defp decode(value, type), do: Codec.decode(value, type)

  defp insert(table, fields) do
    id = Entity.generate_id()

    names = [
      "id",
      "created_at",
      "server_created_at",
      "server_updated_at",
      "updated_at",
      "$revisions"
    ]

    custom = Map.keys(fields)
    columns = Enum.map_join(names ++ custom, ", ", &Mapper.quote_identifier/1)

    slots =
      custom
      |> Enum.with_index(2)
      |> Enum.map_join(fn {name, number} -> ", $#{number}::#{cast(name)}" end)

    statement = """
    INSERT INTO "hologram_data"."#{table}" (#{columns})
    VALUES ($1, now(), now(), now(), now(), '{}'#{slots})
    """

    {:ok, _result} =
      Connection.query(statement, [Codec.encode(id, :uuid) | Enum.map(custom, &fields[&1])])

    id
  end

  defp cast("kind"), do: ~s("hologram_data"."my_app_trip_kind_$enum")

  defp cast("state"), do: ~s("hologram_data"."my_app_trip_state_$enum")

  defp cast("owner_id"), do: "uuid"

  defp cast("parent_id"), do: "uuid"

  defp cast("at"), do: "timestamptz"

  defp cast("day"), do: "date"

  defp cast("budget"), do: "float8"

  defp cast("seats"), do: "int8"

  defp cast("active"), do: "boolean"

  defp cast("starts"), do: "time"

  defp cast("external"), do: "uuid"

  defp cast(_name), do: "text"

  defp prepare do
    model = Model.fold(Model.empty(), @ops)

    :ok =
      run([%{version: "20260813091522", path: "app/migrations/x.ex", ops: @ops}], model, @context)
  end

  defp uuid(id), do: Codec.encode(id, :uuid)

  describe "row-own words" do
    test "split and at, on every edge of the text", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        for text <- @texts do
          fields = if is_nil(text), do: %{"seats" => 0}, else: %{"destination" => text}

          insert("my_app_trip", fields)
        end

        for separator <- [", ", ",", "aa", "%", ".", "ó", "テ"], position <- [0, 1, 2, 3, 100] do
          term =
            {:at, {:split, {:name, [:destination]}, {:value, separator}}, {:value, position}}

          assert_same(term, attribute_target(:string))
        end
      end)
    end

    test "a missing part falling back through coalesce", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        for text <- @texts do
          fields = if is_nil(text), do: %{"seats" => 0}, else: %{"destination" => text}

          insert("my_app_trip", fields)
        end

        term =
          {:coalesce,
           [
             {:at, {:split, {:name, [:destination]}, {:value, ", "}}, {:value, 1}},
             {:value, ""}
           ]}

        assert_same(term, attribute_target(:string))
      end)
    end

    test "joins, with nil and empty operands", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        insert("my_app_trip", %{"first" => "a", "last" => "b"})
        insert("my_app_trip", %{"first" => "a"})
        insert("my_app_trip", %{"last" => "b"})
        insert("my_app_trip", %{"first" => "", "last" => ""})
        insert("my_app_trip", %{"seats" => 1})

        assert_same(
          {:concat, [{:name, [:first]}, {:value, " "}, {:name, [:last]}]},
          attribute_target(:string)
        )

        assert_same(
          {:coalesce, [{:name, [:first]}, {:concat, [{:name, [:last]}, {:value, "!"}]}]},
          attribute_target(:string)
        )
      end)
    end

    test "coalesce over each type, with a literal", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        insert("my_app_trip", %{
          "active" => false,
          "at" => ~U[2026-05-06 07:08:09.123456Z],
          "budget" => 1.5,
          "day" => ~D[2026-05-06],
          "external" => uuid("018f0000-0000-7000-8000-000000000001"),
          "kind" => "old",
          "seats" => 3,
          "starts" => ~T[07:08:09.123456],
          "state" => "live"
        })

        insert("my_app_trip", %{"first" => "only nils"})

        for {field, type, literal} <- [
              {:active, :boolean, true},
              {:budget, :float, 0},
              {:seats, :integer, 7},
              {:day, :date, ~D[2000-01-02]},
              {:at, :datetime, ~U[2000-01-02 03:04:05Z]},
              {:at, :datetime,
               %{
                 ~U[2000-01-02 03:04:05Z]
                 | utc_offset: 3600,
                   zone_abbr: "CET",
                   time_zone: "Europe/Warsaw"
               }},
              {:starts, :time, ~T[10:00:00]},
              {:external, :uuid, "018F0000-0000-7000-8000-00000000000A"}
            ] do
          assert_same({:coalesce, [{:name, [field]}, {:value, literal}]}, attribute_target(type))
        end
      end)
    end

    test "enums copied to another type and coalesced with a literal", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        insert("my_app_trip", %{"state" => "draft"})
        insert("my_app_trip", %{"state" => "live"})
        insert("my_app_trip", %{"seats" => 1})

        wider = attribute_target(:enum, values: [:live, :old, :draft])
        mapping_target = %{wider | name: :kind}

        assert_same({:name, [:state]}, mapping_target)
        assert_same({:coalesce, [{:name, [:state]}, {:value, :live}]}, mapping_target)
      end)
    end
  end

  describe "to-one paths" do
    test "through a reference, nil included, and two hops on a self-relationship", %{
      scratch: scratch
    } do
      route(scratch, fn ->
        prepare()

        named = insert("my_app_user", %{"name" => "Ana"})
        unnamed = insert("my_app_user", %{"name" => nil})

        root = insert("my_app_trip", %{"owner_id" => uuid(named), "first" => "root"})
        child = insert("my_app_trip", %{"parent_id" => uuid(root), "owner_id" => uuid(unnamed)})
        insert("my_app_trip", %{"parent_id" => uuid(child)})
        insert("my_app_trip", %{"seats" => 1})

        assert_same({:name, [:owner, :name]}, attribute_target(:string))
        assert_same({:name, [:parent, :first]}, attribute_target(:string))
        assert_same({:name, [:parent, :parent, :first]}, attribute_target(:string))
        assert_same({:name, [:parent, :owner, :name]}, attribute_target(:string))

        assert_same(
          {:coalesce,
           [{:name, [:owner, :name]}, {:name, [:parent, :owner, :name]}, {:value, "?"}]},
          attribute_target(:string)
        )

        assert_same(
          {:name, [:parent, :owner_id]},
          %{kind: :relationship, line: 9, name: :value, type: MyApp.User}
        )
      end)
    end
  end
end
