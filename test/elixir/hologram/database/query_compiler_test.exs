defmodule Hologram.Database.QueryCompilerTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Database.QueryCompiler

  alias Hologram.Database.Mapper
  alias Hologram.Query
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4

  describe "compile/2" do
    test "assigns placeholders to param slots" do
      mapping = Mapper.derive!([Module2])
      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:param, :search}}]}

      assert %{
               params: [{:param, :search, :string}],
               sql: sql
             } = compile(term, mapping)

      assert String.ends_with?(sql, ~s( WHERE "c" = $1))
    end

    test "compiles equality predicates into bound placeholders" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(a: true, b: 123)
        |> Query.normalize()

      assert compile(term, mapping) == %{
               params: [{:value, true}, {:value, 123}],
               sql:
                 ~s(SELECT "id", "a", "b", "c", "created_at", "updated_at" ) <>
                   ~s(FROM "hologram_data"."test_fixtures_entity_module2" ) <>
                   ~s(WHERE "a" = $1 AND "b" = $2)
             }
    end

    test "binds membership params with list types" do
      mapping = Mapper.derive!([Module2])
      term = %{Query.normalize(Module2) | filter: [{:c, :in, {:param, :names}}]}

      assert %{
               params: [{:param, :names, {:list, :string}}],
               sql: sql
             } = compile(term, mapping)

      assert String.ends_with?(sql, ~s| WHERE "c" = ANY($1)|)
    end

    test "compiles inequality null-inclusively on optional attributes" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(b: {:!=, 3})
        |> Query.normalize()

      assert %{params: [{:value, 3}], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s| WHERE ("b" != $1 OR "b" IS NULL)|)
    end

    test "compiles inequality plainly on required attributes" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(a: {:!=, false})
        |> Query.normalize()

      assert %{params: [{:value, false}], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( WHERE "a" != $1))
    end

    test "compiles membership as an array binding" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(c: ["x", "y"])
        |> Query.normalize()

      assert %{params: [{:value, ["x", "y"]}], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s| WHERE "c" = ANY($1)|)
    end

    test "compiles negated membership null-inclusively on optional attributes" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(b: {:not_in, [1, 2]})
        |> Query.normalize()

      assert %{params: [{:value, [1, 2]}], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s| WHERE ("b" != ALL($1) OR "b" IS NULL)|)
    end

    test "compiles nil-holding membership into the IS NULL branch" do
      mapping = Mapper.derive!([Module2])
      term = %{Query.normalize(Module2) | filter: [{:b, :in, [nil, 1]}]}

      assert %{params: [{:value, [1]}], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s| WHERE ("b" = ANY($1) OR "b" IS NULL)|)
    end

    test "compiles nil-holding negated membership into the value-requiring branch" do
      mapping = Mapper.derive!([Module2])
      term = %{Query.normalize(Module2) | filter: [{:b, :not_in, [nil, 1]}]}

      assert %{params: [{:value, [1]}], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s| WHERE ("b" != ALL($1) AND "b" IS NOT NULL)|)
    end

    test "compiles nil-only membership as IS NULL without a bind slot" do
      mapping = Mapper.derive!([Module2])
      term = %{Query.normalize(Module2) | filter: [{:b, :in, [nil]}]}

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( WHERE "b" IS NULL))
    end

    test "compiles nil-only negated membership as IS NOT NULL without a bind slot" do
      mapping = Mapper.derive!([Module2])
      term = %{Query.normalize(Module2) | filter: [{:b, :not_in, [nil]}]}

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( WHERE "b" IS NOT NULL))
    end

    test "compiles nil equality as IS NULL without a bind slot" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(b: nil)
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( WHERE "b" IS NULL))
    end

    test "compiles nil inequality as IS NOT NULL without a bind slot" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(b: {:!=, nil})
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( WHERE "b" IS NOT NULL))
    end

    test "compiles ordering comparisons null-exclusively" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(b: [{:>=, 3}, {:<, 10}])
        |> Query.normalize()

      assert %{params: [{:value, 10}, {:value, 3}], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( WHERE "b" < $1 AND "b" >= $2))
    end

    test "encodes literal values with the attribute's codec type" do
      mapping = Mapper.derive!([Module4])

      term =
        Module4
        |> Query.filter(c: :x)
        |> Query.normalize()

      assert %{params: [{:value, "x"}], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( WHERE "c" = $1))
    end

    test "mixes literal and param bindings in placeholder order" do
      mapping = Mapper.derive!([Module2])

      term = %{
        Query.normalize(Module2)
        | filter: [{:a, :==, true}, {:c, :==, {:param, :search}}]
      }

      assert %{
               params: [{:value, true}, {:param, :search, :string}],
               sql: sql
             } = compile(term, mapping)

      assert String.ends_with?(sql, ~s( WHERE "a" = $1 AND "c" = $2))
    end

    test "selects the mapped columns in physical order" do
      mapping = Mapper.derive!([Module2])
      term = Query.normalize(Module2)

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s(SELECT "id", "a", "b", "c", "created_at", "updated_at" FROM "hologram_data"."test_fixtures_entity_module2")
             }
    end

    test "selects reference columns for to-one relationships" do
      mapping = Mapper.derive!([Module2, Module3])
      term = Query.normalize(Module3)

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s(SELECT "id", "b_id", "c_id", "created_at", "updated_at" FROM "hologram_data"."test_fixtures_entity_module3")
             }
    end
  end
end
