defmodule Hologram.Database.QueryCompilerTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Database.QueryCompiler

  alias Hologram.Database.Mapper
  alias Hologram.Query
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Entity.Module5

  describe "compile/2" do
    test "assigns placeholders to param slots" do
      mapping = Mapper.derive!([Module2])
      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:param, :search}}]}

      assert %{
               params: [{:param, :search, :string}],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(sql, ~s( WHERE "c" = $1))
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
                   ~s(WHERE "a" = $1 AND "b" = $2 ORDER BY "id" ASC)
             }
    end

    test "applies nested clauses to a to-many include" do
      mapping = Mapper.derive!([Module1, Module2, Module3])

      term =
        Module3
        |> Query.include(:a, fn related_query ->
          related_query
          |> Query.filter(a: true)
          |> Query.order_by(:c)
          |> Query.limit(5)
        end)
        |> Query.normalize()

      assert %{params: [{:value, true}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( AND "a" = $1 ORDER BY "c" ASC, "id" ASC LIMIT 5))
      assert String.contains?(sql, ~s|ORDER BY "i1"."c" ASC, "i1"."id" ASC), '[]'::jsonb|)
    end

    test "binds membership params with list types" do
      mapping = Mapper.derive!([Module2])
      term = %{Query.normalize(Module2) | filter: [{:c, :in, {:param, :names}}]}

      assert %{
               params: [{:param, :names, {:list, :string}}],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(sql, ~s| WHERE "c" = ANY($1)|)
    end

    test "compiles inequality null-inclusively on optional attributes" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(b: {:!=, 3})
        |> Query.normalize()

      assert %{params: [{:value, 3}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE ("b" != $1 OR "b" IS NULL)|)
    end

    test "compiles inequality plainly on required attributes" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(a: {:!=, false})
        |> Query.normalize()

      assert %{params: [{:value, false}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "a" != $1))
    end

    test "compiles limit and offset as literal bounds" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.limit(50)
        |> Query.offset(20)
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( ORDER BY "id" ASC LIMIT 50 OFFSET 20))
    end

    test "compiles membership as an array binding" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(c: ["x", "y"])
        |> Query.normalize()

      assert %{params: [{:value, ["x", "y"]}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE "c" = ANY($1)|)
    end

    test "compiles negated membership null-inclusively on optional attributes" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(b: {:not_in, [1, 2]})
        |> Query.normalize()

      assert %{params: [{:value, [1, 2]}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE ("b" != ALL($1) OR "b" IS NULL)|)
    end

    test "compiles nil-holding membership into the IS NULL branch" do
      mapping = Mapper.derive!([Module2])
      term = %{Query.normalize(Module2) | filter: [{:b, :in, [nil, 1]}]}

      assert %{params: [{:value, [1]}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE ("b" = ANY($1) OR "b" IS NULL)|)
    end

    test "compiles nil-holding negated membership into the value-requiring branch" do
      mapping = Mapper.derive!([Module2])
      term = %{Query.normalize(Module2) | filter: [{:b, :not_in, [nil, 1]}]}

      assert %{params: [{:value, [1]}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE ("b" != ALL($1) AND "b" IS NOT NULL)|)
    end

    test "compiles nil-only membership as IS NULL without a bind slot" do
      mapping = Mapper.derive!([Module2])
      term = %{Query.normalize(Module2) | filter: [{:b, :in, [nil]}]}

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "b" IS NULL))
    end

    test "compiles nil-only negated membership as IS NOT NULL without a bind slot" do
      mapping = Mapper.derive!([Module2])
      term = %{Query.normalize(Module2) | filter: [{:b, :not_in, [nil]}]}

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "b" IS NOT NULL))
    end

    test "aliases sibling includes distinctly" do
      mapping = Mapper.derive!([Module1, Module2, Module3])

      term =
        Module3
        |> Query.include(:b)
        |> Query.include(:c)
        |> Query.normalize()

      assert %{sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|FROM "hologram_data"."test_fixtures_entity_module2" AS "i1" WHERE "i1"."id" = "test_fixtures_entity_module3"."b_id") AS "b"|
             )

      assert String.contains?(
               sql,
               ~s|FROM "hologram_data"."test_fixtures_entity_module1" AS "i2" WHERE "i2"."id" = "test_fixtures_entity_module3"."c_id") AS "c"|
             )
    end

    test "compiles counting queries as a bare count" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(a: true)
        |> Query.count()
        |> Query.normalize()

      assert compile(term, mapping) == %{
               params: [{:value, true}],
               sql:
                 ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_entity_module2" WHERE "a" = $1|
             }
    end

    test "compiles counting over view bounds as a capped subquery" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.limit(50)
        |> Query.count()
        |> Query.normalize()

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s|SELECT count(*) FROM (SELECT 1 FROM "hologram_data"."test_fixtures_entity_module2" LIMIT 50) AS "sub"|
             }
    end

    test "embeds a to-many relationship as an aggregated array" do
      mapping = Mapper.derive!([Module1, Module2, Module3])

      term =
        Module3
        |> Query.include(:a)
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)

      expected_fragment =
        ~s|(SELECT COALESCE(jsonb_agg(jsonb_build_object(| <>
          ~s|'id', "i1"."id", 'a', "i1"."a", 'b', "i1"."b", 'c', "i1"."c", | <>
          ~s|'created_at', "i1"."created_at", 'updated_at', "i1"."updated_at"| <>
          ~s|) ORDER BY "i1"."id" ASC), '[]'::jsonb) | <>
          ~s|FROM (SELECT "t1".* | <>
          ~s|FROM "hologram_data"."test_fixtures_entity_module3_a_$join" AS "j1" | <>
          ~s|JOIN "hologram_data"."test_fixtures_entity_module2" AS "t1" | <>
          ~s|ON "t1"."id" = "j1"."target_id" | <>
          ~s|WHERE "j1"."source_id" = "test_fixtures_entity_module3"."id" | <>
          ~s|ORDER BY "id" ASC) AS "i1") AS "a"|

      assert String.contains?(sql, expected_fragment)
    end

    test "embeds a to-one relationship as a jsonb subselect" do
      mapping = Mapper.derive!([Module1, Module2, Module3])

      term =
        Module3
        |> Query.include(:c)
        |> Query.normalize()

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s|SELECT "id", "b_id", "c_id", "created_at", "updated_at", | <>
                   ~s|(SELECT jsonb_build_object('id', "i1"."id", 'created_at', "i1"."created_at", 'updated_at', "i1"."updated_at") | <>
                   ~s|FROM "hologram_data"."test_fixtures_entity_module1" AS "i1" | <>
                   ~s|WHERE "i1"."id" = "test_fixtures_entity_module3"."c_id") AS "c" | <>
                   ~s|FROM "hologram_data"."test_fixtures_entity_module3" ORDER BY "id" ASC|
             }
    end

    test "embeds a self-referencing to-one unambiguously" do
      mapping = Mapper.derive!([Module3, Module5])

      term =
        Module5
        |> Query.include(:b)
        |> Query.normalize()

      assert %{sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|FROM "hologram_data"."test_fixtures_entity_module5" AS "i1" WHERE "i1"."id" = "test_fixtures_entity_module5"."b_id") AS "b"|
             )
    end

    test "compiles nil equality as IS NULL without a bind slot" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(b: nil)
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "b" IS NULL))
    end

    test "compiles nil inequality as IS NOT NULL without a bind slot" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(b: {:!=, nil})
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "b" IS NOT NULL))
    end

    test "compiles ordering comparisons null-exclusively" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(b: [{:>=, 3}, {:<, 10}])
        |> Query.normalize()

      assert %{params: [{:value, 10}, {:value, 3}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "b" < $1 AND "b" >= $2))
    end

    test "compiles single-result queries with a unit limit" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.filter(a: true)
        |> Query.one()
        |> Query.normalize()

      assert %{params: [{:value, true}], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( WHERE "a" = $1 ORDER BY "id" ASC LIMIT 1))
    end

    test "compiles ordering keys with directions and the id tiebreaker" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.order_by(b: :desc, c: :asc)
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( ORDER BY "b" DESC, "c" ASC, "id" ASC))
    end

    test "compiles single-result queries with a zero limit as zero" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.limit(0)
        |> Query.one()
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( ORDER BY "id" ASC LIMIT 0))
    end

    test "encodes literal values with the attribute's codec type" do
      mapping = Mapper.derive!([Module4])

      term =
        Module4
        |> Query.filter(c: :x)
        |> Query.normalize()

      assert %{params: [{:value, "x"}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "c" = $1))
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

      assert String.contains?(sql, ~s( WHERE "a" = $1 AND "c" = $2))
    end

    test "omits includes from counting queries" do
      mapping = Mapper.derive!([Module1, Module2, Module3])

      term =
        Module3
        |> Query.include(:c)
        |> Query.count()
        |> Query.normalize()

      assert compile(term, mapping) == %{
               params: [],
               sql: ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_entity_module3"|
             }
    end

    test "selects the mapped columns in physical order" do
      mapping = Mapper.derive!([Module2])
      term = Query.normalize(Module2)

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s(SELECT "id", "a", "b", "c", "created_at", "updated_at" FROM "hologram_data"."test_fixtures_entity_module2" ORDER BY "id" ASC)
             }
    end

    test "selects reference columns for to-one relationships" do
      mapping = Mapper.derive!([Module2, Module3])
      term = Query.normalize(Module3)

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s(SELECT "id", "b_id", "c_id", "created_at", "updated_at" FROM "hologram_data"."test_fixtures_entity_module3" ORDER BY "id" ASC)
             }
    end

    test "threads include params after the root's" do
      mapping = Mapper.derive!([Module1, Module2, Module3])

      base_term =
        Module3
        |> Query.include(:a, &Query.filter(&1, a: true))
        |> Query.normalize()

      term = %{base_term | filter: [{:id, :==, {:param, :root_id}}]}

      assert %{params: [{:param, :root_id, :uuid}, {:value, true}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(sql, ~s( WHERE "id" = $1))
      assert String.contains?(sql, ~s( AND "a" = $2))
    end
  end
end
