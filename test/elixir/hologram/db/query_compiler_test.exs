defmodule Hologram.DB.QueryCompilerTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.Query

  import Hologram.DB.QueryCompiler

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Mapper
  alias Hologram.Policy
  alias Hologram.Query
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Entity.Module5
  alias Hologram.Test.Fixtures.Entity.Module6
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2
  alias Hologram.Test.Fixtures.Role

  describe "compile/2" do
    test "assigns placeholders to placeholder slots" do
      mapping = Mapper.derive!([Module2])
      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:placeholder, :search}}]}

      assert %{
               params: [{:placeholder, :search, :string}],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(sql, ~s( WHERE "c" = $1))
    end

    test "compiles equality predicates into bound placeholders" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> filter(a: true, b: 123)
        |> Query.normalize()

      assert compile(term, mapping) == %{
               params: [{:value, true}, {:value, 123}],
               sql:
                 ~s(SELECT "id", "a", "b", "c", "created_at", "updated_at", "c_$sort" ) <>
                   ~s(FROM "hologram_data"."test_fixtures_entity_module2" ) <>
                   ~s(WHERE "a" = $1 AND "b" = $2 ORDER BY "id" ASC)
             }
    end

    test "applies nested clauses to a to-many include" do
      mapping = Mapper.derive!([Module1, Module2, Module3])

      term =
        Module3
        |> include(:a, fn related_query ->
          related_query
          |> filter(a: true)
          |> order_by(:c)
          |> limit(5)
        end)
        |> Query.normalize()

      assert %{params: [{:value, true}], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s( AND "a" = $1 ORDER BY "c_$sort" ASC, "c" ASC, "id" ASC LIMIT 5)
             )

      assert String.contains?(
               sql,
               ~s|ORDER BY "i1"."c_$sort" ASC, "i1"."c" ASC, "i1"."id" ASC), '[]'::jsonb|
             )
    end

    test "applies the sort-key companion to a to-many include ordering" do
      mapping = Mapper.derive!([Module1, Module2, Module3])

      term =
        Module3
        |> include(:a, fn related_query -> order_by(related_query, :c) end)
        |> Query.normalize()

      assert %{sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|ORDER BY "i1"."c_$sort" ASC, "i1"."c" ASC, "i1"."id" ASC), '[]'::jsonb|
             )
    end

    test "binds membership element placeholders as scalar slots in an array constructor" do
      mapping = Mapper.derive!([Module2])
      term = %{Query.normalize(Module2) | filter: [{:b, :in, [{:placeholder, :bound}, 1]}]}

      assert %{params: placeholders, sql: sql} = compile(term, mapping)
      assert placeholders == [{:placeholder, :bound, :integer}, {:value, 1}]
      assert String.contains?(sql, ~s|WHERE "b" = ANY(ARRAY[$1, $2]::int8[])|)
    end

    test "binds membership element placeholders under the nil-inclusive branch" do
      mapping = Mapper.derive!([Module2])
      term = %{Query.normalize(Module2) | filter: [{:b, :in, [nil, {:placeholder, :bound}]}]}

      assert %{params: [{:placeholder, :bound, :integer}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(sql, ~s|("b" = ANY(ARRAY[$1]::int8[]) OR "b" IS NULL)|)
    end

    test "binds membership placeholders with list types" do
      mapping = Mapper.derive!([Module2])
      term = %{Query.normalize(Module2) | filter: [{:c, :in, {:placeholder, :names}}]}

      assert %{
               params: [{:placeholder, :names, {:list, :string}}],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(sql, ~s| WHERE "c" = ANY($1)|)
    end

    test "compiles a to-one reference field predicate against its reference column" do
      mapping = Mapper.derive!([Module1, Module2, Module3])

      term =
        Module3
        |> filter(c_id: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")
        |> Query.normalize()

      assert compile(term, mapping) == %{
               params: [
                 {:value,
                  <<1, 143, 69, 113, 161, 178, 124, 61, 142, 79, 90, 107, 124, 141, 158, 15>>}
               ],
               sql:
                 ~s(SELECT "id", "b_id", "c_id", "created_at", "updated_at" ) <>
                   ~s(FROM "hologram_data"."test_fixtures_entity_module3" ) <>
                   ~s(WHERE "c_id" = $1 ORDER BY "id" ASC)
             }
    end

    test "binds a to-one reference field placeholder as a uuid slot" do
      mapping = Mapper.derive!([Module1, Module2, Module3])
      term = %{Query.normalize(Module3) | filter: [{:c_id, :==, {:placeholder, :owner}}]}

      assert %{
               params: [{:placeholder, :owner, :uuid}],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(sql, ~s( WHERE "c_id" = $1))
    end

    test "composes a policy rule after the authored filter" do
      mapping = Mapper.derive!([Module1, Module2, Module3])

      term =
        Module2
        |> filter(a: true)
        |> Query.normalize()

      rules = [%{predicates: [{:c, :==, "text_1"}], to: nil, via: nil}]

      assert compile(term, mapping, %{operation: :read, rules: rules}) == %{
               params: [{:value, true}, {:value, "text_1"}],
               sql:
                 ~s(SELECT "id", "a", "b", "c", "created_at", "updated_at", "c_$sort" ) <>
                   ~s(FROM "hologram_data"."test_fixtures_entity_module2" ) <>
                   ~s(WHERE "a" = $1 AND "c" = $2 ORDER BY "id" ASC)
             }
    end

    test "composes several policy rules as an OR group" do
      mapping = Mapper.derive!([Module2])
      term = Query.normalize(Module2)

      rules = [
        %{predicates: [{:a, :==, true}], to: nil, via: nil},
        %{predicates: [{:b, :>=, 3}, {:c, :==, "text_2"}], to: nil, via: nil}
      ]

      assert %{sql: sql} = compile(term, mapping, %{operation: :read, rules: rules})

      assert String.contains?(sql, ~s|WHERE (("a" = $1) OR ("b" >= $2 AND "c" = $3))|)
    end

    test "drops the policy group for an unconditional rule" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> filter(a: true)
        |> Query.normalize()

      rules = [%{predicates: [], to: nil, via: nil}]

      assert %{sql: sql} = compile(term, mapping, %{operation: :read, rules: rules})

      assert String.contains?(sql, ~s|WHERE "a" = $1 ORDER BY|)
    end

    test "drops the placeholders bound by the rules of a group an unconditional rule satisfies" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> filter(a: true)
        |> Query.normalize()

      conditional_rule = %{predicates: [{:b, :>=, 3}], to: nil, via: nil}
      unconditional_rule = %{predicates: [], to: nil, via: nil}

      for rules <- [
            [conditional_rule, unconditional_rule],
            [unconditional_rule, conditional_rule]
          ] do
        assert %{params: placeholders, sql: sql} =
                 compile(term, mapping, %{operation: :read, rules: rules})

        assert placeholders == [value: true]
        assert String.contains?(sql, ~s|WHERE "a" = $1 ORDER BY|)
      end
    end

    test "composes the included type's read policy into the include subquery, keyed on its alias" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant])

      term =
        PolicyModule1
        |> include(:parent)
        |> Query.normalize()

      rules = [%{predicates: [], to: nil, via: nil}]

      assert %{sql: sql} = compile(term, mapping, %{operation: :read, rules: rules})

      assert String.contains?(
               sql,
               ~s|WHERE "i1"."id" = "test_fixtures_policy_module1"."parent_id" | <>
                 ~s|AND EXISTS (SELECT 1 FROM "hologram_data"."hologram_role_grant" AS "rg" | <>
                 ~s|WHERE "rg"."user_id" = $1 | <>
                 ~s|AND "rg"."role" = ANY($2::"hologram_data"."hologram_role_grant_role_$enum"[]) | <>
                 ~s|AND "rg"."resource_type" = | <>
                 ~s|$3::"hologram_data"."hologram_role_grant_resource_type_$enum" | <>
                 ~s|AND ("rg"."resource_id" = "i1"."id" OR "rg"."resource_id" IS NULL))|
             )
    end

    test "leaves include subqueries unfiltered without a policy" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant])

      term =
        PolicyModule1
        |> include(:parent)
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|WHERE "i1"."id" = "test_fixtures_policy_module1"."parent_id")|
             )
    end

    test "denies everything for a policy with no rules" do
      mapping = Mapper.derive!([Module2])
      term = Query.normalize(Module2)

      assert %{params: [], sql: sql} =
               compile(term, mapping, %{operation: :read, rules: []})

      assert String.contains?(sql, " WHERE FALSE ORDER BY")
    end

    test "binds one reserved slot for every actor reference" do
      mapping = Mapper.derive!([Module1, Module2, Module3])
      term = Query.normalize(Module3)

      rules = [
        %{predicates: [{:b_id, :==, {:actor}}], to: nil, via: nil},
        %{predicates: [{:c_id, :==, {:actor}}], to: nil, via: nil}
      ]

      assert %{params: [:actor], sql: sql} =
               compile(term, mapping, %{operation: :read, rules: rules})

      assert String.contains?(sql, ~s|WHERE (("b_id" = $1) OR ("c_id" = $1))|)
    end

    test "allocates the actor slot after the authored placeholders" do
      mapping = Mapper.derive!([Module1, Module2, Module3])

      term = %{Query.normalize(Module3) | filter: [{:c_id, :==, {:placeholder, :target}}]}

      rules = [%{predicates: [{:b_id, :==, {:actor}}], to: nil, via: nil}]

      assert %{params: [{:placeholder, :target, :uuid}, :actor], sql: sql} =
               compile(term, mapping, %{operation: :read, rules: rules})

      assert String.contains?(sql, ~s|WHERE "c_id" = $1 AND "b_id" = $2|)
    end

    test "composes a policy into a counting query before aggregation" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> Query.count()
        |> Query.normalize()

      rules = [%{predicates: [{:a, :==, true}], to: nil, via: nil}]

      assert compile(term, mapping, %{operation: :read, rules: rules}) == %{
               params: [{:value, true}],
               sql:
                 ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_entity_module2" | <>
                   ~s|WHERE "a" = $1|
             }
    end

    test "composes an own-roles grant reference as an EXISTS over the grant store" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant])
      term = Query.normalize(PolicyModule1)

      rules = [%{predicates: [], to: [{:own, [:editor, :owner]}], via: nil}]

      assert compile(term, mapping, %{operation: :read, rules: rules}) == %{
               params: [
                 :actor,
                 {:value, ["editor", "owner"]},
                 {:value, "test_fixtures_policy_module1"}
               ],
               sql:
                 ~s|SELECT "id", "priority", "public", "author_id", "parent_id", | <>
                   ~s|"created_at", "updated_at" | <>
                   ~s|FROM "hologram_data"."test_fixtures_policy_module1" | <>
                   ~s|WHERE EXISTS (SELECT 1 FROM "hologram_data"."hologram_role_grant" AS "rg" | <>
                   ~s|WHERE "rg"."user_id" = $1 | <>
                   ~s|AND "rg"."role" = ANY($2::"hologram_data"."hologram_role_grant_role_$enum"[]) | <>
                   ~s|AND "rg"."resource_type" = | <>
                   ~s|$3::"hologram_data"."hologram_role_grant_resource_type_$enum" | <>
                   ~s|AND ("rg"."resource_id" = "test_fixtures_policy_module1"."id" | <>
                   ~s|OR "rg"."resource_id" IS NULL)) ORDER BY "id" ASC|
             }
    end

    test "composes a global grant reference as an uncorrelated grant-store lookup" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant])
      term = Query.normalize(PolicyModule2)

      rules = [%{predicates: [], to: [{:global, [Role.Module1, Role.Module2]}], via: nil}]

      assert compile(term, mapping, %{operation: :archive, rules: rules}) == %{
               params: [
                 :actor,
                 {:value,
                  ["Hologram.Test.Fixtures.Role.Module1", "Hologram.Test.Fixtures.Role.Module2"]}
               ],
               sql:
                 ~s|SELECT "id", "public", "created_at", "updated_at" | <>
                   ~s|FROM "hologram_data"."test_fixtures_policy_module2" | <>
                   ~s|WHERE EXISTS (SELECT 1 FROM "hologram_data"."hologram_role_grant" AS "rg" | <>
                   ~s|WHERE "rg"."user_id" = $1 | <>
                   ~s|AND "rg"."role" = ANY($2::"hologram_data"."hologram_role_grant_role_$enum"[]) | <>
                   ~s|AND "rg"."resource_type" IS NULL AND "rg"."resource_id" IS NULL) | <>
                   ~s|ORDER BY "id" ASC|
             }
    end

    test "elides a global grant reference for an anonymous session" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant])
      term = Query.normalize(PolicyModule2)

      rules = [%{predicates: [], to: [{:global, [Role.Module1]}], via: nil}]

      assert %{params: placeholders, sql: sql} =
               compile(term, mapping, %{operation: :archive, rules: rules, anonymous?: true})

      assert placeholders == []
      refute String.contains?(sql, "hologram_role_grant")
    end

    test "composes a namespaced grant reference as a type-wide lookup" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant])
      term = Query.normalize(PolicyModule1)

      rules = [%{predicates: [], to: [{:type, PolicyModule2, [:admin]}], via: nil}]

      assert %{params: placeholders, sql: sql} =
               compile(term, mapping, %{operation: :read, rules: rules})

      assert placeholders == [
               :actor,
               {:value, ["admin"]},
               {:value, "test_fixtures_policy_module2"}
             ]

      assert String.contains?(
               sql,
               ~s|AND "rg"."resource_type" = $3::"hologram_data"."hologram_role_grant_resource_type_$enum" | <>
                 ~s|AND "rg"."resource_id" IS NULL)|
             )
    end

    test "composes a relationship grant reference against the reference column" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant])
      term = Query.normalize(PolicyModule1)

      rules = [%{predicates: [], to: [{:rel, :parent, [:admin]}], via: nil}]

      assert %{params: placeholders, sql: sql} =
               compile(term, mapping, %{operation: :read, rules: rules})

      assert placeholders == [
               :actor,
               {:value, ["admin"]},
               {:value, "test_fixtures_policy_module2"}
             ]

      assert String.contains?(
               sql,
               ~s|AND "rg"."resource_id" = "test_fixtures_policy_module1"."parent_id")|
             )
    end

    test "composes grant references and predicates as one conjunction" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant])
      term = Query.normalize(PolicyModule1)

      rules = [%{predicates: [{:priority, :>=, 3}], to: [{:own, [:editor]}], via: nil}]

      assert %{sql: sql} = compile(term, mapping, %{operation: :read, rules: rules})

      assert String.contains?(sql, ~s|WHERE "priority" >= $1 AND EXISTS (SELECT 1|)
    end

    test "composes several grant references of one rule as an OR group" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant])
      term = Query.normalize(PolicyModule1)

      rules = [
        %{predicates: [], to: [{:own, [:viewer]}, {:type, PolicyModule2, [:admin]}], via: nil}
      ]

      assert %{sql: sql} = compile(term, mapping, %{operation: :read, rules: rules})

      assert String.contains?(sql, ~s|WHERE ((EXISTS (SELECT 1|)
      assert String.contains?(sql, ~s|) OR (EXISTS (SELECT 1|)
    end

    test "composes a delegation as an EXISTS over the related entity's policy" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant])
      term = Query.normalize(PolicyModule1)

      rules = [%{predicates: [], to: nil, via: :parent}]

      assert compile(term, mapping, %{operation: :publish, rules: rules}) == %{
               params: [{:value, true}],
               sql:
                 ~s|SELECT "id", "priority", "public", "author_id", "parent_id", | <>
                   ~s|"created_at", "updated_at" | <>
                   ~s|FROM "hologram_data"."test_fixtures_policy_module1" | <>
                   ~s|WHERE EXISTS (SELECT 1 FROM "hologram_data"."test_fixtures_policy_module2" | <>
                   ~s|WHERE "test_fixtures_policy_module2"."id" = | <>
                   ~s|"test_fixtures_policy_module1"."parent_id" AND "public" = $1) | <>
                   ~s|ORDER BY "id" ASC|
             }
    end

    test "denies a delegation to an operation the related entity type does not grant" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant])
      term = Query.normalize(PolicyModule1)

      rules = [%{predicates: [], to: nil, via: :parent}]

      assert %{sql: sql} = compile(term, mapping, %{operation: :delete, rules: rules})

      assert String.contains?(
               sql,
               ~s|"test_fixtures_policy_module1"."parent_id" AND FALSE)|
             )
    end

    test "composes a delegation alongside the rule's own predicates" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant])
      term = Query.normalize(PolicyModule1)

      rules = [%{predicates: [{:priority, :>=, 3}], to: nil, via: :parent}]

      assert %{params: placeholders, sql: sql} =
               compile(term, mapping, %{operation: :publish, rules: rules})

      assert placeholders == [{:value, 3}, {:value, true}]
      assert String.contains?(sql, ~s|WHERE "priority" >= $1 AND EXISTS (SELECT 1|)
    end

    test "composes the delegated policy's grant references with the shared actor slot" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant])
      term = Query.normalize(PolicyModule1)

      rules = [
        %{predicates: [], to: [{:own, [:owner]}], via: nil},
        %{predicates: [], to: nil, via: :parent}
      ]

      assert %{params: placeholders, sql: sql} =
               compile(term, mapping, %{operation: :read, rules: rules})

      assert Enum.count(placeholders, &(&1 == :actor)) == 1

      assert String.contains?(
               sql,
               ~s|EXISTS (SELECT 1 FROM "hologram_data"."test_fixtures_policy_module2" | <>
                 ~s|WHERE "test_fixtures_policy_module2"."id" = | <>
                 ~s|"test_fixtures_policy_module1"."parent_id" AND EXISTS (SELECT 1 FROM | <>
                 ~s|"hologram_data"."hologram_role_grant" AS "rg" WHERE "rg"."user_id" = $1|
             )
    end

    test "composes the grant store's own visibility policy" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant])
      term = Query.normalize(RoleGrant)
      policy = %{operation: :read, rules: Policy.build(RoleGrant)[:read]}

      assert %{params: placeholders, sql: sql} = compile(term, mapping, policy)

      assert placeholders == [
               :actor,
               {:value, "test_fixtures_policy_module1"},
               {:value, ["owner"]},
               {:value, "test_fixtures_policy_module1"},
               {:value, "test_fixtures_policy_module2"},
               {:value, ["member"]},
               {:value, "test_fixtures_policy_module2"}
             ]

      assert String.contains?(sql, ~s|WHERE (("user_id" = $1)|)

      assert String.contains?(
               sql,
               ~s|("resource_type" = $2 AND EXISTS (SELECT 1 FROM | <>
                 ~s|"hologram_data"."hologram_role_grant" AS "rg" WHERE "rg"."user_id" = $1 | <>
                 ~s|AND "rg"."role" = ANY($3::"hologram_data"."hologram_role_grant_role_$enum"[]) | <>
                 ~s|AND "rg"."resource_type" = | <>
                 ~s|$4::"hologram_data"."hologram_role_grant_resource_type_$enum" | <>
                 ~s|AND "rg"."resource_id" = "hologram_role_grant"."resource_id"))|
             )
    end

    test "compiles inequality null-inclusively on optional attributes" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> filter(b: {:!=, 3})
        |> Query.normalize()

      assert %{params: [{:value, 3}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE ("b" != $1 OR "b" IS NULL)|)
    end

    test "compiles inequality plainly on required attributes" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> filter(a: {:!=, false})
        |> Query.normalize()

      assert %{params: [{:value, false}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "a" != $1))
    end

    test "compiles limit and offset as literal bounds" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> limit(50)
        |> offset(20)
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( ORDER BY "id" ASC LIMIT 50 OFFSET 20))
    end

    test "compiles membership as an array binding" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> filter(c: ["x", "y"])
        |> Query.normalize()

      assert %{params: [{:value, ["x", "y"]}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE "c" = ANY($1)|)
    end

    test "compiles negated membership null-inclusively on optional attributes" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> filter(b: {:not_in, [1, 2]})
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
        |> include(:b)
        |> include(:c)
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
        |> filter(a: true)
        |> count()
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
        |> limit(50)
        |> count()
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
        |> include(:a)
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)

      expected_fragment =
        ~s|(SELECT COALESCE(jsonb_agg(jsonb_build_object(| <>
          ~s|'id', "i1"."id", 'a', "i1"."a", 'b', "i1"."b", 'c', "i1"."c", | <>
          ~s|'created_at', "i1"."created_at", 'updated_at', "i1"."updated_at", | <>
          ~s|'c_$sort', "i1"."c_$sort"| <>
          ~s|) ORDER BY "i1"."id" ASC), '[]'::jsonb) | <>
          ~s|FROM (SELECT "t1".* | <>
          ~s|FROM "hologram_data"."test_fixtures_entity_module2" AS "t1" | <>
          ~s|WHERE "t1"."id" IN (SELECT "j1"."target_id" | <>
          ~s|FROM "hologram_data"."test_fixtures_entity_module3_a_$join" AS "j1" | <>
          ~s|WHERE "j1"."source_id" = "test_fixtures_entity_module3"."id") | <>
          ~s|ORDER BY "id" ASC) AS "i1") AS "a"|

      assert String.contains?(sql, expected_fragment)
    end

    test "embeds a to-one relationship as a jsonb subselect" do
      mapping = Mapper.derive!([Module1, Module2, Module3])

      term =
        Module3
        |> include(:c)
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
        |> include(:b)
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
        |> filter(b: nil)
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "b" IS NULL))
    end

    test "compiles nil inequality as IS NOT NULL without a bind slot" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> filter(b: {:!=, nil})
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "b" IS NOT NULL))
    end

    test "compiles ordering comparisons null-exclusively" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> filter(b: [{:>=, 3}, {:<, 10}])
        |> Query.normalize()

      assert %{params: [{:value, 10}, {:value, 3}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "b" < $1 AND "b" >= $2))
    end

    test "compiles single-result queries with a unit limit" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> filter(a: true)
        |> one()
        |> Query.normalize()

      assert %{params: [{:value, true}], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( WHERE "a" = $1 ORDER BY "id" ASC LIMIT 1))
    end

    test "compiles ordering keys with directions and the id tiebreaker" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> order_by(b: :desc, c: :asc)
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( ORDER BY "b" DESC, "c_$sort" ASC, "c" ASC, "id" ASC))
    end

    test "compiles string ordering through the sort-key companion" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> order_by(c: :desc)
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( ORDER BY "c_$sort" DESC, "c" DESC, "id" ASC))
    end

    test "compiles single-result queries with a zero limit as zero" do
      mapping = Mapper.derive!([Module2])

      term =
        Module2
        |> limit(0)
        |> one()
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( ORDER BY "id" ASC LIMIT 0))
    end

    test "encodes literal values with the attribute's codec type" do
      mapping = Mapper.derive!([Module4])

      term =
        Module4
        |> filter(c: :x)
        |> Query.normalize()

      assert %{params: [{:value, "x"}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "c" = $1))
    end

    test "mixes literal and placeholder bindings in placeholder order" do
      mapping = Mapper.derive!([Module2])

      term = %{
        Query.normalize(Module2)
        | filter: [{:a, :==, true}, {:c, :==, {:placeholder, :search}}]
      }

      assert %{
               params: [{:value, true}, {:placeholder, :search, :string}],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(sql, ~s( WHERE "a" = $1 AND "c" = $2))
    end

    test "nests a to-one inside a to-one include" do
      mapping = Mapper.derive!([Module2, Module3, Module5])

      term =
        Module5
        |> include(a: :b)
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)

      expected_fragment =
        ~s|, 'b', (SELECT jsonb_build_object(| <>
          ~s|'id', "i2"."id", 'a', "i2"."a", 'b', "i2"."b", 'c', "i2"."c", | <>
          ~s|'created_at', "i2"."created_at", 'updated_at', "i2"."updated_at", | <>
          ~s|'c_$sort', "i2"."c_$sort"| <>
          ~s|) FROM "hologram_data"."test_fixtures_entity_module2" AS "i2" | <>
          ~s|WHERE "i2"."id" = "i1"."b_id")|

      assert String.contains?(sql, expected_fragment)
    end

    test "nests an include inside a to-many aggregation" do
      mapping = Mapper.derive!([Module2, Module3, Module6])

      term =
        Module6
        |> include(a: :b)
        |> Query.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|, 'b', (SELECT jsonb_build_object('id', "i2"."id"|
             )

      assert String.contains?(sql, ~s|AS "i2" WHERE "i2"."id" = "i1"."b_id")|)

      assert String.contains?(
               sql,
               ~s|FROM "hologram_data"."test_fixtures_entity_module6_a_$join" AS "j1"|
             )
    end

    test "omits includes from counting queries" do
      mapping = Mapper.derive!([Module1, Module2, Module3])

      term =
        Module3
        |> include(:c)
        |> count()
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
                 ~s(SELECT "id", "a", "b", "c", "created_at", "updated_at", "c_$sort" FROM "hologram_data"."test_fixtures_entity_module2" ORDER BY "id" ASC)
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

    test "threads include placeholders after the root's" do
      mapping = Mapper.derive!([Module1, Module2, Module3])

      base_term =
        Module3
        |> include(:a, &filter(&1, a: true))
        |> Query.normalize()

      term = %{base_term | filter: [{:id, :==, {:placeholder, :root_id}}]}

      assert %{params: [{:placeholder, :root_id, :uuid}, {:value, true}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(sql, ~s( WHERE "id" = $1))
      assert String.contains?(sql, ~s( AND "a" = $2))
    end
  end
end
