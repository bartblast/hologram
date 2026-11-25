defmodule Hologram.Migration.Value.SQLTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Migration.Value.SQL

  alias Hologram.DB.Codec
  alias Hologram.DB.Mapper

  @uuid "018f0000-0000-7000-8000-000000000000"

  @model %{
    entities: %{
      MyApp.Trip => %{
        attributes: [
          {:kind, :enum, [values: [:draft, :live, :old]]},
          {:state, :enum, [values: [:draft, :live]]},
          {:title, :string, []}
        ],
        relationships: [
          {:owner, MyApp.User, []},
          {:parent, MyApp.Trip, [optional: true]},
          {:tags, [MyApp.Tag], []}
        ],
        roles: [],
        uniques: []
      },
      MyApp.Tag => %{
        attributes: [{:label, :string, []}, {:rank, :integer, []}],
        relationships: [],
        roles: [],
        uniques: []
      },
      MyApp.User => %{
        attributes: [{:name, :string, []}],
        relationships: [],
        roles: [],
        uniques: []
      }
    },
    roles: %{},
    user_entity: nil
  }

  @state {:enum, MyApp.Trip, :state, [:draft, :live]}

  defp mapping, do: Mapper.derive_from_model!(@model)

  defp rendered(
         term,
         type,
         target \\ %{kind: :attribute, line: 1, name: :title, opts: [], type: :string}
       ) do
    {sql, "", params} = render(%{term: term, type: type}, MyApp.Trip, mapping(), target)

    {sql, params}
  end

  describe "render/4" do
    test "reads a column of the row" do
      assert rendered({:name, [:title], :string}, :string) == {~s("$r0"."title"), []}
    end

    test "reads a reference" do
      assert rendered({:name, [:owner_id], :uuid}, :uuid) == {~s("$r0"."owner_id"), []}
    end

    test "reads a system column" do
      assert rendered({:name, [:created_at], :datetime}, :datetime) ==
               {~s("$r0"."created_at"), []}
    end

    test "reads through a to-one in a subquery" do
      assert rendered({:name, [:owner, :name], :string}, :string) ==
               {~s|(SELECT "$r1"."name" FROM "hologram_data"."my_app_user" AS "$r1" | <>
                  ~s|WHERE "$r1"."id" = "$r0"."owner_id")|, []}
    end

    test "gives each hop an alias of its own on a self-relationship" do
      {sql, []} = rendered({:name, [:parent, :parent, :title], :string}, :string)

      assert sql =~ ~s("$r1"."id" = "$r0"."parent_id")
      assert sql =~ ~s("$r2"."id" = "$r1"."parent_id")
      assert sql =~ ~s(SELECT "$r2"."title")
    end

    test "binds a string value cast to text" do
      term = {:concat, [{:value, "to ", :string}, {:name, [:title], :string}]}

      assert rendered(term, :string) == {~s|($1::text \|\| "$r0"."title")|, ["to "]}
    end

    test "numbers the parameters in order" do
      term =
        {:coalesce,
         [{:value, "a", :string}, {:concat, [{:value, "b", :string}, {:value, "c", :string}]}]}

      assert rendered(term, :string) ==
               {"COALESCE($1::text, ($2::text || $3::text))", ["a", "b", "c"]}
    end

    test "casts each type of value" do
      for {value, type, sql_type} <- [
            {true, :boolean, "boolean"},
            {~D[2026-01-01], :date, "date"},
            {1.5, :float, "float8"},
            {1, :integer, "int8"},
            {~T[10:00:00.000000], :time, "time"}
          ] do
        assert rendered({:value, value, type}, type) == {"$1::#{sql_type}", [value]}
      end
    end

    test "encodes a datetime" do
      value = ~U[2026-01-01 00:00:00.000000Z]

      assert rendered({:value, value, :datetime}, :datetime) == {"$1::timestamptz", [value]}
    end

    test "encodes a uuid" do
      assert rendered({:value, @uuid, :uuid}, :uuid) ==
               {"$1::uuid", [Codec.encode(@uuid, :uuid)]}
    end

    test "encodes a reference as a uuid" do
      type = {:reference, MyApp.User}

      assert rendered({:value, @uuid, type}, type) == {"$1::uuid", [Codec.encode(@uuid, :uuid)]}
    end

    test "casts an enum value to its schema-qualified type" do
      target = %{
        kind: :attribute,
        line: 1,
        name: :state,
        opts: [values: [:draft, :live]],
        type: :enum
      }

      assert {sql, ["live"]} = rendered({:value, :live, @state}, @state, target)
      assert sql == ~s($1::"hologram_data"."my_app_trip_state_$enum")
    end

    test "renders a part of a split" do
      term =
        {:at, {:split, {:name, [:title], :string}, {:value, ", ", :string}},
         {:value, 1, :integer}}

      assert rendered(term, :string) ==
               {~s|(string_to_array($1::text \|\| ("$r0"."title"), $1::text))[3]|, [", "]}
    end

    test "counts a stored to-many through its join table" do
      assert rendered({:count, {:relationship, [:tags]}}, :integer) ==
               {~s|(SELECT COUNT(*) FROM "hologram_data"."my_app_trip_tags_$join" AS "$j1" | <>
                  ~s|WHERE "$j1"."source_id" = "$r0"."id")|, []}
    end

    test "counts a to-many through a to-one by its reference" do
      {sql, []} = rendered({:count, {:relationship, [:parent, :tags]}}, :integer)

      assert sql =~ ~s("$j1"."source_id" = "$r0"."parent_id")
    end

    test "reads a to-many two hops away through a subquery" do
      {sql, []} = rendered({:count, {:relationship, [:parent, :parent, :tags]}}, :integer)

      assert sql =~ ~s|"$j1"."source_id" = (SELECT "$r1"."parent_id" |
    end

    test "orders the most common string by its sort key and then itself" do
      term = {:most_common, {:relationship, [:tags]}, :label, :string, nil}

      assert rendered(term, :string) ==
               {~s|(SELECT "$r1"."label" FROM "hologram_data"."my_app_tag" AS "$r1" | <>
                  ~s|JOIN "hologram_data"."my_app_trip_tags_$join" AS "$j1" | <>
                  ~s|ON "$j1"."target_id" = "$r1"."id" WHERE "$j1"."source_id" = "$r0"."id" | <>
                  ~s|AND "$r1"."label" IS NOT NULL | <>
                  ~s|GROUP BY "$r1"."label" | <>
                  ~s|ORDER BY COUNT(*) DESC, MIN("$r1"."label_$sort"), "$r1"."label" LIMIT 1)|,
                []}
    end

    test "orders any other most common value by itself" do
      term = {:most_common, {:relationship, [:tags]}, :rank, :integer, nil}

      {sql, []} = rendered(term, :integer)

      assert sql =~ ~s|GROUP BY "$r1"."rank" ORDER BY COUNT(*) DESC, "$r1"."rank" LIMIT 1|
    end

    test "casts an enum of another attribute to the target's type" do
      target = %{
        kind: :attribute,
        line: 1,
        name: :kind,
        opts: [values: [:draft, :live, :old]],
        type: :enum
      }

      assert {sql, []} = rendered({:name, [:state], @state}, @state, target)
      assert sql == ~s|("$r0"."state")::text::"hologram_data"."my_app_trip_kind_$enum"|
    end

    test "leaves an enum of the target's own attribute uncast" do
      target = %{
        kind: :attribute,
        line: 1,
        name: :state,
        opts: [values: [:draft, :live]],
        type: :enum
      }

      assert rendered({:name, [:state], @state}, @state, target) == {~s("$r0"."state"), []}
    end
  end

  describe "render/4, the rows pointing at this one" do
    @target %{kind: :attribute, line: 1, name: :title, opts: [], type: :string}

    @count_target %{kind: :attribute, line: 1, name: :rank, opts: [], type: :integer}

    @count {:count, {:referencing, MyApp.Trip, :parent}}

    @most_common {:most_common, {:referencing, MyApp.Trip, :parent}, :title, :string, nil}

    test "joins one aggregate for a count, with no subquery per row" do
      assert render(%{term: @count, type: :integer}, MyApp.Trip, mapping(), @count_target) ==
               {~s|COALESCE("$a0".v, 0)|,
                ~s|LEFT JOIN (SELECT "parent_id" AS k, COUNT(*) AS v | <>
                  ~s|FROM "hologram_data"."my_app_trip" WHERE "parent_id" IS NOT NULL | <>
                  ~s|GROUP BY "parent_id") AS "$a0" ON "$a0".k = "$r0"."id"|, []}
    end

    test "joins one aggregate for a most_common, ordered as the word orders" do
      {fragment, joins, []} =
        render(%{term: @most_common, type: :string}, MyApp.Trip, mapping(), @target)

      assert fragment == ~s("$a0".v)

      assert joins ==
               ~s|LEFT JOIN (SELECT DISTINCT ON (k) k, v FROM (SELECT "parent_id" AS k, | <>
                 ~s|"title" AS v, COUNT(*) AS n, MIN("title_$sort") AS s | <>
                 ~s|FROM "hologram_data"."my_app_trip" WHERE "parent_id" IS NOT NULL | <>
                 ~s|AND "title" IS NOT NULL GROUP BY "parent_id", "title") AS grouped | <>
                 ~s|ORDER BY k, n DESC, s, v) AS "$a0" ON "$a0".k = "$r0"."id"|
    end

    test "joins a word used twice once" do
      term = {:coalesce, [@most_common, @most_common]}

      {fragment, joins, []} = render(%{term: term, type: :string}, MyApp.Trip, mapping(), @target)

      assert fragment == ~s|COALESCE("$a0".v, "$a0".v)|
      assert length(String.split(joins, "LEFT JOIN")) == 2
    end

    test "names the sort key the word orders by" do
      assert sort_keys(%{term: @most_common}, MyApp.Trip, mapping()) == [
               %{op: :add_column, table: "my_app_trip", column: "title_$sort"}
             ]
    end
  end

  describe "fill_statement/4" do
    @table "my_app_trip"

    test "writes every row of a statement with no joins" do
      assert fill_statement(@table, "title", {"$1::text", "", ["a"]}) ==
               ~s|UPDATE "hologram_data"."my_app_trip" AS "$r0" SET "title" = $1::text|
    end

    test "writes only the rows holding NULL, returning their ids" do
      assert fill_statement(@table, "title", {"$1::text", "", ["a"]},
               nulls_only: true,
               returning: true
             ) ==
               ~s|UPDATE "hologram_data"."my_app_trip" AS "$r0" SET "title" = $1::text | <>
                 ~s|WHERE "$r0"."title" IS NULL RETURNING "$r0"."id"|
    end

    test "reads the row through a self-join when it has joins" do
      assert fill_statement(@table, "rank", {~s|"$a0".v|, "LEFT JOIN x", []}) ==
               ~s|UPDATE "hologram_data"."my_app_trip" AS "$u" SET "rank" = "$a0".v | <>
                 ~s|FROM "hologram_data"."my_app_trip" AS "$r0" LEFT JOIN x | <>
                 ~s|WHERE "$u"."id" = "$r0"."id"|
    end

    test "writes only the rows holding NULL through a self-join, returning their ids" do
      assert fill_statement(@table, "rank", {~s|"$a0".v|, "LEFT JOIN x", []},
               nulls_only: true,
               returning: true
             ) ==
               ~s|UPDATE "hologram_data"."my_app_trip" AS "$u" SET "rank" = "$a0".v | <>
                 ~s|FROM "hologram_data"."my_app_trip" AS "$r0" LEFT JOIN x | <>
                 ~s|WHERE "$u"."id" = "$r0"."id" AND "$u"."rank" IS NULL RETURNING "$u"."id"|
    end
  end

  describe "enum_uses/4" do
    setup do
      [
        target: %{
          kind: :attribute,
          line: 1,
          name: :kind,
          opts: [values: [:draft, :live, :old]],
          type: :enum
        }
      ]
    end

    test "lists a literal under its own type, nested or not", %{target: target} do
      term = {:coalesce, [{:name, [:state], @state}, {:value, :live, @state}]}

      assert enum_uses(%{term: term, type: @state}, MyApp.Trip, mapping(), %{
               target
               | name: :state,
                 opts: [values: [:draft, :live]]
             }) == [{"my_app_trip_state_$enum", "live"}]
    end

    test "lists every value a copy casts into the target's type", %{target: target} do
      assert enum_uses(
               %{term: {:name, [:state], @state}, type: @state},
               MyApp.Trip,
               mapping(),
               target
             ) ==
               [{"my_app_trip_kind_$enum", "draft"}, {"my_app_trip_kind_$enum", "live"}]
    end

    test "lists nothing for a read of the target's own type", %{target: target} do
      own = {:enum, MyApp.Trip, :kind, [:draft, :live, :old]}

      assert enum_uses(%{term: {:name, [:kind], own}, type: own}, MyApp.Trip, mapping(), target) ==
               []
    end
  end

  describe "sort_keys/3" do
    test "names the sort key a most_common of a string orders by" do
      term = {:most_common, {:relationship, [:tags]}, :label, :string, nil}

      assert sort_keys(%{term: term}, MyApp.Trip, mapping()) ==
               [%{op: :add_column, table: "my_app_tag", column: "label_$sort"}]
    end

    test "finds it inside another word" do
      term =
        {:coalesce,
         [{:most_common, {:relationship, [:tags]}, :label, :string, nil}, {:value, "x", :string}]}

      assert [%{column: "label_$sort"}] = sort_keys(%{term: term}, MyApp.Trip, mapping())
    end

    test "names a sort key two words order by once" do
      most_common = {:most_common, {:relationship, [:tags]}, :label, :string, nil}

      assert sort_keys(%{term: {:coalesce, [most_common, most_common]}}, MyApp.Trip, mapping()) ==
               [%{op: :add_column, table: "my_app_tag", column: "label_$sort"}]
    end

    test "names nothing for a value with no sort key" do
      term = {:most_common, {:relationship, [:tags]}, :rank, :integer, nil}

      assert sort_keys(%{term: term}, MyApp.Trip, mapping()) == []
    end
  end
end
