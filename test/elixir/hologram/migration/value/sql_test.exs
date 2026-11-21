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
        relationships: [{:owner, MyApp.User, []}, {:parent, MyApp.Trip, [optional: true]}],
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
    render(%{term: term, type: type}, MyApp.Trip, mapping(), target)
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
               {~s|(CASE WHEN "$r0"."title" = '' THEN NULL::text | <>
                  ~s|ELSE (string_to_array("$r0"."title", $1::text))[2] END)|, [", "]}
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
end
