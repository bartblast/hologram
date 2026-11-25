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
  alias Hologram.DB.SortKey
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
    top_grade: {:enum, [values: [MyApp.Abc, MyApp.Zed]]},
    kind: {:enum, [values: [:live, :old, :draft]]},
    last: {:string, []},
    seats: {:integer, []},
    state: {:enum, [values: [:draft, :live]]},
    starts: {:time, []},
    tier: {:enum, [values: [:abc, :mid, :zed]]}
  ]

  # Declared so that the order of the values differs from the order of their labels.
  @tag_attributes [
    code: {:integer, []},
    flag: {:boolean, []},
    grade: {:enum, [values: [MyApp.Zed, MyApp.Abc]]},
    label: {:string, []},
    level: {:enum, [values: [:zed, :mid, :abc]]},
    moment: {:datetime, []},
    on_day: {:date, []},
    ref: {:uuid, []},
    ratio: {:float, []},
    time_of_day: {:time, []}
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
         %{op: :create_entity, entity: MyApp.Tag, line: 2}
       ] ++
         Enum.map(@tag_attributes, fn {name, {type, opts}} ->
           %{
             op: :add_attribute,
             entity: MyApp.Tag,
             name: name,
             type: type,
             opts: [{:optional, true} | opts],
             line: 2
           }
         end) ++
         [
           %{
             op: :add_relationship,
             entity: MyApp.Tag,
             name: :guide,
             type: MyApp.User,
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
           },
           %{
             op: :add_relationship,
             entity: MyApp.Trip,
             name: :tags,
             type: [MyApp.Tag],
             opts: [],
             line: 7
           },
           %{
             op: :add_relationship,
             entity: MyApp.Trip,
             name: :friends,
             type: [MyApp.Trip],
             opts: [],
             line: 8
           },
           %{
             op: :add_relationship,
             entity: MyApp.Tag,
             name: :trip,
             type: MyApp.Trip,
             opts: [optional: true],
             line: 9
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
    {fragment, joins, params} = SQL.render(resolved, MyApp.Trip, mapping, target)

    statement = """
    SELECT "$r0"."id", #{fragment}
    FROM "hologram_data"."my_app_trip" AS "$r0" #{joins}
    ORDER BY "$r0"."id"
    """

    {:ok, %{rows: rows}} = Connection.query(statement, params)

    # The joins must keep each trip once: a row they drop or repeat would hide in the map.
    {:ok, %{rows: id_rows}} =
      Connection.query(~s|SELECT "id" FROM "hologram_data"."my_app_trip" ORDER BY "id"|)

    ids = Enum.map(id_rows, fn [id] -> Codec.decode(id, :uuid) end)

    assert Enum.map(rows, fn [id, _value] -> Codec.decode(id, :uuid) end) == ids

    from_sql =
      Map.new(rows, fn [id, value] ->
        {Codec.decode(id, :uuid), decode(value, resolved.type)}
      end)

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

  defp cast("level"), do: ~s("hologram_data"."my_app_tag_level_$enum")

  defp cast("grade"), do: ~s("hologram_data"."my_app_tag_grade_$enum")

  defp cast("code"), do: "int8"

  defp cast("flag"), do: "boolean"

  defp cast("guide_id"), do: "uuid"

  defp cast("moment"), do: "timestamptz"

  defp cast("on_day"), do: "date"

  defp cast("ref"), do: "uuid"

  defp cast("time_of_day"), do: "time"

  defp cast("kind"), do: ~s("hologram_data"."my_app_trip_kind_$enum")

  defp cast("state"), do: ~s("hologram_data"."my_app_trip_state_$enum")

  defp cast("owner_id"), do: "uuid"

  defp cast("parent_id"), do: "uuid"

  defp cast("trip_id"), do: "uuid"

  defp cast("at"), do: "timestamptz"

  defp cast("day"), do: "date"

  defp cast("budget"), do: "float8"

  defp cast("seats"), do: "int8"

  defp cast("active"), do: "boolean"

  defp cast("starts"), do: "time"

  defp cast("external"), do: "uuid"

  defp cast(_name), do: "text"

  defp insert_edge(relationship, source_id, target_id) do
    {:ok, _result} =
      Connection.query(
        ~s|INSERT INTO "hologram_data"."my_app_trip_#{relationship}_$join" | <>
          ~s|("source_id", "target_id") VALUES ($1, $2)|,
        [uuid(source_id), uuid(target_id)]
      )
  end

  # A trip holding one tag for each given map of fields. A string's sort key goes in beside it,
  # as a write stores it.
  defp insert_trip_with_tags(tags) do
    trip = insert("my_app_trip", %{"seats" => 1})

    for fields <- tags do
      with_key =
        case fields do
          %{"label" => label} when is_binary(label) ->
            Map.put_new(fields, "label_$sort", SortKey.compute(label))

          _other ->
            fields
        end

      insert_edge("tags", trip, insert("my_app_tag", with_key))
    end

    trip
  end

  # A trip with one tag pointing at it for each given map of fields, its string's sort key beside
  # it, as a write stores it.
  defp insert_trip_pointed_at(tags) do
    trip = insert("my_app_trip", %{"seats" => 1})

    for fields <- tags do
      with_key =
        case fields do
          %{"label" => label} when is_binary(label) ->
            Map.put_new(fields, "label_$sort", SortKey.compute(label))

          _other ->
            fields
        end

      insert("my_app_tag", Map.put(with_key, "trip_id", uuid(trip)))
    end

    trip
  end

  defp most_common(attribute), do: {:most_common, {:relationship, [:tags]}, attribute}

  defp pointing_common(attribute) do
    {:most_common, {:referencing, MyApp.Tag, :trip}, attribute}
  end

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

  describe "the rows pointing at this one" do
    test "count, over none and some, leaving out rows pointing elsewhere", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        insert_trip_pointed_at([])
        insert_trip_pointed_at([%{"code" => 1}])
        insert_trip_pointed_at([%{"code" => 1}, %{"code" => 2}, %{"code" => 3}])
        insert("my_app_tag", %{"code" => 9})

        assert_same(
          {:count, {:referencing, MyApp.Tag, :trip}},
          attribute_target(:integer)
        )
      end)
    end

    test "count on a self-reference", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        root = insert("my_app_trip", %{"seats" => 1})
        child = insert("my_app_trip", %{"parent_id" => uuid(root)})
        insert("my_app_trip", %{"parent_id" => uuid(root)})
        insert("my_app_trip", %{"parent_id" => uuid(child)})

        assert_same(
          {:count, {:referencing, MyApp.Trip, :parent}},
          attribute_target(:integer)
        )
      end)
    end

    test "most_common of strings, on ties and sort order", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        for labels <- [
              [],
              [nil, nil],
              ["a"],
              ["a", "b", "b"],
              [nil, nil, "a"],
              ["Zebra", "apple"],
              ["apple", "Zebra"],
              ["Apple", "apple"],
              ["żółć", "zebra"],
              ["e\u0301", "é"],
              ["b", "a", "b", "a", "c"]
            ] do
          insert_trip_pointed_at(Enum.map(labels, &%{"label" => &1}))
        end

        assert_same(pointing_common(:label), attribute_target(:string))
      end)
    end

    test "most_common orders an enum by declared position, not its label", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        for levels <- [["abc", "zed"], ["zed", "abc"], ["mid", "abc", "mid"], []] do
          insert_trip_pointed_at(Enum.map(levels, &%{"level" => &1}))
        end

        # Copied into an enum declaring the same values in another order, so the copy can't lean
        # on the target's order.
        target = %{attribute_target(:enum, values: [:abc, :mid, :zed]) | name: :tier}

        assert_same(pointing_common(:level), target)
      end)
    end

    test "most_common orders module-valued enum values by declared position", %{
      scratch: scratch
    } do
      route(scratch, fn ->
        prepare()

        for grades <- [
              [MyApp.Abc, MyApp.Zed],
              [MyApp.Zed, MyApp.Abc],
              [MyApp.Abc, MyApp.Abc, MyApp.Zed]
            ] do
          insert_trip_pointed_at(Enum.map(grades, &%{"grade" => Codec.encode(&1, :enum)}))
        end

        target = %{attribute_target(:enum, values: [MyApp.Abc, MyApp.Zed]) | name: :top_grade}

        assert_same(pointing_common(:grade), target)
      end)
    end

    test "most_common of integers on a tie", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        for codes <- [[2, 1], [1, 2, 2], [3, 3, 1, 1]] do
          insert_trip_pointed_at(Enum.map(codes, &%{"code" => &1}))
        end

        assert_same(pointing_common(:code), attribute_target(:integer))
      end)
    end
  end

  describe "stored sets" do
    test "count, over none, some, through a to-one and a nil one", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        empty = insert_trip_with_tags([])
        some = insert_trip_with_tags([%{"label" => "a"}, %{"label" => "b"}])
        insert("my_app_trip", %{"parent_id" => uuid(some)})
        insert("my_app_trip", %{"parent_id" => uuid(empty)})

        assert_same({:count, {:relationship, [:tags]}}, attribute_target(:integer))
        assert_same({:count, {:relationship, [:parent, :tags]}}, attribute_target(:integer))
      end)
    end

    test "count over a join table on a self-relationship", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        first = insert("my_app_trip", %{"seats" => 1})
        second = insert("my_app_trip", %{"seats" => 2})
        insert("my_app_trip", %{"seats" => 3})

        insert_edge("friends", first, second)
        insert_edge("friends", first, first)
        insert_edge("friends", second, first)

        assert_same({:count, {:relationship, [:friends]}}, attribute_target(:integer))

        assert_same(
          {:most_common, {:relationship, [:friends]}, :seats},
          attribute_target(:integer)
        )
      end)
    end

    test "most_common of strings, on ties and sort order", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        for labels <- [
              [],
              [nil, nil],
              ["a"],
              ["a", "b", "b"],
              [nil, nil, "a"],
              ["Zebra", "apple"],
              ["apple", "Zebra"],
              ["Apple", "apple"],
              ["apple", "Apple", "apple"],
              ["żółć", "zebra"],
              ["é", "e", "f"],
              ["e\u0301", "é"],
              ["b", "a", "b", "a", "c"]
            ] do
          insert_trip_with_tags(Enum.map(labels, &%{"label" => &1}))
        end

        assert_same(most_common(:label), attribute_target(:string))
      end)
    end

    test "most_common counts one value stored under two sort keys once", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        # An upgrade can change the key computed for a value, leaving older rows on the old one.
        insert_trip_with_tags([
          %{"label" => "a"},
          %{"label" => "a"},
          %{"label" => "c"},
          %{"label" => "c"},
          %{"label" => "c", "label_$sort" => "older key"}
        ])

        assert_same(most_common(:label), attribute_target(:string))
      end)
    end

    test "most_common orders an enum by declared position, not its label", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        for levels <- [["abc", "zed"], ["zed", "abc"], ["mid", "abc"], ["abc", "abc", "zed"], []] do
          insert_trip_with_tags(Enum.map(levels, &%{"level" => &1}))
        end

        # Copied into an enum declaring the same values in another order, so the copy can't lean
        # on the target's order.
        target = %{attribute_target(:enum, values: [:abc, :mid, :zed]) | name: :tier}

        assert_same(most_common(:level), target)
      end)
    end

    test "most_common of every other type it takes", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        first_user = insert("my_app_user", %{"name" => "a"})
        second_user = insert("my_app_user", %{"name" => "b"})

        insert_trip_with_tags([%{"code" => 3}, %{"code" => 1}, %{"code" => 3}])
        insert_trip_with_tags([%{"code" => 2}, %{"code" => -1}])
        insert_trip_with_tags([%{"flag" => true}, %{"flag" => false}])
        insert_trip_with_tags([%{"flag" => true}, %{"flag" => true}, %{"flag" => false}])
        insert_trip_with_tags([%{"on_day" => ~D[2026-01-01]}, %{"on_day" => ~D[2025-12-31]}])

        insert_trip_with_tags([
          %{"moment" => ~U[2026-01-01 00:00:00.000000Z]},
          %{"moment" => ~U[2025-12-31 23:59:59.999999Z]}
        ])

        insert_trip_with_tags([
          %{"time_of_day" => ~T[10:00:00.000000]},
          %{"time_of_day" => ~T[09:00:00.000000]}
        ])

        insert_trip_with_tags([
          %{"ref" => uuid("018f0000-0000-7000-8000-00000000000b")},
          %{"ref" => uuid("018f0000-0000-7000-8000-00000000000a")}
        ])

        insert_trip_with_tags([
          %{"guide_id" => uuid(first_user)},
          %{"guide_id" => uuid(second_user)}
        ])

        assert_same(most_common(:code), attribute_target(:integer))
        assert_same(most_common(:flag), attribute_target(:boolean))
        assert_same(most_common(:on_day), attribute_target(:date))
        assert_same(most_common(:moment), attribute_target(:datetime))
        assert_same(most_common(:time_of_day), attribute_target(:time))
        assert_same(most_common(:ref), attribute_target(:uuid))

        assert_same(
          most_common(:guide_id),
          %{kind: :relationship, line: 9, name: :value, type: MyApp.User}
        )
      end)
    end
  end
end
