defmodule Hologram.DB.QueryCompilerTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.DB

  import Hologram.DB.QueryCompiler

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Mapper
  alias Hologram.Policy
  alias Hologram.Query
  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module24
  alias Hologram.Test.Fixtures.Entity.Module25
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Entity.Module5
  alias Hologram.Test.Fixtures.Entity.Module6
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2
  alias Hologram.Test.Fixtures.Policy.Module5, as: PolicyModule5
  alias Hologram.Test.Fixtures.Policy.Module8, as: PolicyModule8
  alias Hologram.Test.Fixtures.Policy.Module9, as: PolicyModule9
  alias Hologram.Test.Fixtures.Role

  defp hop(number, entity_type, selected, correlated_on) do
    ~s|(SELECT #{selected} FROM #{table(entity_type)} AS "$p#{number}" | <>
      ~s|WHERE "$p#{number}"."id" = #{correlated_on})|
  end

  # Every path test reads its hops out of these mappings - a hop's table has to be mapped to be read.
  defp path_mapping(entity_types), do: Mapper.derive!(entity_types, [])

  defp path_term(entity_type, predicates) do
    entity_type
    |> Stage.filter(predicates)
    |> Stage.normalize()
  end

  defp table(entity_type), do: ~s("hologram_data"."#{Mapper.table_name(entity_type)}")

  describe "compile/2" do
    test "assigns placeholders to placeholder slots" do
      mapping = Mapper.derive!([Module2], [])
      term = %{Stage.normalize(Module2) | filter: [{:c, :==, {:placeholder, :search}}]}

      assert %{
               params: [{:placeholder, :search, :string}],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(sql, ~s( WHERE "c" = $1))
    end

    test "compiles equality predicates into bound placeholders" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(a: true, b: 123)
        |> Stage.normalize()

      assert compile(term, mapping) == %{
               params: [{:value, true}, {:value, 123}],
               sql:
                 ~s(SELECT "id", "a", "b", "c", "created_at", "updated_at", "$revisions", "c_$sort" ) <>
                   ~s(FROM "hologram_data"."test_fixtures_entity_module2" ) <>
                   ~s(WHERE "a" = $1 AND "b" = $2 ORDER BY "id" ASC)
             }
    end

    test "applies nested clauses to a to-many include" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term =
        Module3
        |> include(a, fn related_query ->
          related_query
          |> filter(a: true)
          |> order_by(c)
          |> limit(5)
        end)
        |> Stage.normalize()

      assert %{params: [{:value, true}], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s( AND "a" = $1 ORDER BY "c_$sort" ASC, "c" ASC, "id" ASC LIMIT 5)
             )

      assert String.contains?(
               sql,
               ~s|ORDER BY "$i1"."c_$sort" ASC, "$i1"."c" ASC, "$i1"."id" ASC), '[]'::jsonb|
             )
    end

    test "applies the sort-key companion to a to-many include ordering" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term =
        Module3
        |> include(a, fn related_query -> order_by(related_query, c) end)
        |> Stage.normalize()

      assert %{sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|ORDER BY "$i1"."c_$sort" ASC, "$i1"."c" ASC, "$i1"."id" ASC), '[]'::jsonb|
             )
    end

    test "binds membership element placeholders as scalar slots in an array constructor" do
      mapping = Mapper.derive!([Module2], [])
      term = %{Stage.normalize(Module2) | filter: [{:b, :in, [{:placeholder, :bound}, 1]}]}

      assert %{params: placeholders, sql: sql} = compile(term, mapping)
      assert placeholders == [{:placeholder, :bound, :integer}, {:value, 1}]
      assert String.contains?(sql, ~s|WHERE "b" = ANY(ARRAY[$1, $2]::int8[])|)
    end

    test "binds membership element placeholders under the nil-inclusive branch" do
      mapping = Mapper.derive!([Module2], [])
      term = %{Stage.normalize(Module2) | filter: [{:b, :in, [nil, {:placeholder, :bound}]}]}

      assert %{params: [{:placeholder, :bound, :integer}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(sql, ~s|("b" = ANY(ARRAY[$1]::int8[]) OR "b" IS NULL)|)
    end

    test "binds membership placeholders with list types" do
      mapping = Mapper.derive!([Module2], [])
      term = %{Stage.normalize(Module2) | filter: [{:c, :in, {:placeholder, :names}}]}

      assert %{
               params: [{:placeholder, :names, {:list, :string}}],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(sql, ~s| WHERE "c" = ANY($1)|)
    end

    test "compiles a to-one reference field predicate against its reference column" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term =
        Module3
        |> filter(c_id: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")
        |> Stage.normalize()

      assert compile(term, mapping) == %{
               params: [
                 {:value,
                  <<1, 143, 69, 113, 161, 178, 124, 61, 142, 79, 90, 107, 124, 141, 158, 15>>}
               ],
               sql:
                 ~s(SELECT "id", "b_id", "c_id", "created_at", "updated_at", "$revisions" ) <>
                   ~s(FROM "hologram_data"."test_fixtures_entity_module3" ) <>
                   ~s(WHERE "c_id" = $1 ORDER BY "id" ASC)
             }
    end

    test "binds a to-one reference field placeholder as a uuid slot" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])
      term = %{Stage.normalize(Module3) | filter: [{:c_id, :==, {:placeholder, :owner}}]}

      assert %{
               params: [{:placeholder, :owner, :uuid}],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(sql, ~s( WHERE "c_id" = $1))
    end

    test "composes a policy rule after the authored filter" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term =
        Module2
        |> filter(a: true)
        |> Stage.normalize()

      rules = [%{predicates: [{:c, :==, "text_1"}], to: nil, via: nil}]

      assert compile(term, mapping, %{rules: rules}) == %{
               params: [{:value, true}, {:value, "text_1"}],
               sql:
                 ~s(SELECT "id", "a", "b", "c", "created_at", "updated_at", "$revisions", "c_$sort" ) <>
                   ~s(FROM "hologram_data"."test_fixtures_entity_module2" ) <>
                   ~s(WHERE "a" = $1 AND "c" = $2 ORDER BY "id" ASC)
             }
    end

    test "composes several policy rules as an OR group" do
      mapping = Mapper.derive!([Module2], [])
      term = Stage.normalize(Module2)

      rules = [
        %{predicates: [{:a, :==, true}], to: nil, via: nil},
        %{predicates: [{:b, :>=, 3}, {:c, :==, "text_2"}], to: nil, via: nil}
      ]

      assert %{sql: sql} = compile(term, mapping, %{rules: rules})

      assert String.contains?(sql, ~s|WHERE (("a" = $1) OR ("b" >= $2 AND "c" = $3))|)
    end

    test "composes a rule whose condition holds a disjunction one level deeper" do
      mapping = Mapper.derive!([Module2], [])
      term = Stage.normalize(Module2)

      rules = [
        %{predicates: [{:or, [[{:a, :==, true}], [{:b, :>=, 3}]]}], to: nil, via: nil},
        %{predicates: [{:c, :==, "x"}], to: nil, via: nil}
      ]

      assert %{params: params, sql: sql} =
               compile(term, mapping, %{rules: rules})

      assert params == [{:value, true}, {:value, 3}, {:value, "x"}]
      assert String.contains?(sql, ~s|WHERE (((("a" = $1) OR ("b" >= $2))) OR ("c" = $3))|)
    end

    # Nobody is the actor, so the alternative asking about the actor is false and the other
    # alternative stands alone - with no actor slot to bind.
    test "keeps the alternative of an anonymous rule's disjunction that names no actor" do
      mapping = Mapper.derive!([Module2], [])
      term = Stage.normalize(Module2)

      rules = [
        %{predicates: [{:or, [[{:id, :==, {:actor}}], [{:a, :==, true}]]}], to: nil, via: nil}
      ]

      assert %{params: [{:value, true}], sql: sql} =
               compile(term, mapping, %{anonymous?: true, rules: rules})

      assert String.contains?(sql, ~s|WHERE "a" = $1 ORDER BY|)
    end

    # The kept alternative holds a nested disjunction that folds to its one actor-free alternative,
    # and the clauses left splice into the rule.
    test "folds a nested disjunction of an anonymous rule into the clauses that remain" do
      mapping = Mapper.derive!([Module2], [])
      term = Stage.normalize(Module2)

      predicates = [
        {:or,
         [
           [{:id, :==, {:actor}}],
           [{:or, [[{:id, :!=, {:actor}}], [{:a, :==, true}]]}, {:b, :>=, 3}]
         ]}
      ]

      rules = [%{predicates: predicates, to: nil, via: nil}]

      assert %{params: [{:value, true}, {:value, 3}], sql: sql} =
               compile(term, mapping, %{anonymous?: true, rules: rules})

      assert String.contains?(sql, ~s|WHERE "a" = $1 AND "b" >= $2 ORDER BY|)
    end

    test "keeps several actor-free alternatives of an anonymous rule's disjunction" do
      mapping = Mapper.derive!([Module2], [])
      term = Stage.normalize(Module2)

      predicates = [{:or, [[{:id, :==, {:actor}}], [{:a, :==, true}], [{:b, :>=, 3}]]}]
      rules = [%{predicates: predicates, to: nil, via: nil}]

      assert %{params: [{:value, true}, {:value, 3}], sql: sql} =
               compile(term, mapping, %{anonymous?: true, rules: rules})

      assert String.contains?(sql, ~s|WHERE (("a" = $1) OR ("b" >= $2)) ORDER BY|)
    end

    test "drops an anonymous rule whose every alternative names the actor" do
      mapping = Mapper.derive!([Module2], [])
      term = Stage.normalize(Module2)

      predicates = [{:or, [[{:id, :==, {:actor}}], [{:id, :!=, {:actor}}]]}]
      rules = [%{predicates: predicates, to: nil, via: nil}]

      assert %{params: [], sql: sql} =
               compile(term, mapping, %{anonymous?: true, rules: rules})

      assert String.contains?(sql, ~s|WHERE FALSE ORDER BY|)
    end

    test "drops an anonymous rule whose conjunction names the actor beside a disjunction" do
      mapping = Mapper.derive!([Module2], [])
      term = Stage.normalize(Module2)

      predicates = [{:or, [[{:a, :==, true}], [{:b, :>=, 3}]]}, {:id, :==, {:actor}}]
      rules = [%{predicates: predicates, to: nil, via: nil}]

      assert %{params: [], sql: sql} =
               compile(term, mapping, %{anonymous?: true, rules: rules})

      assert String.contains?(sql, ~s|WHERE FALSE ORDER BY|)
    end

    test "drops the policy group for an unconditional rule" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(a: true)
        |> Stage.normalize()

      rules = [%{predicates: [], to: nil, via: nil}]

      assert %{sql: sql} = compile(term, mapping, %{rules: rules})

      assert String.contains?(sql, ~s|WHERE "a" = $1 ORDER BY|)
    end

    test "drops the placeholders bound by the rules of a group an unconditional rule satisfies" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(a: true)
        |> Stage.normalize()

      conditional_rule = %{predicates: [{:b, :>=, 3}], to: nil, via: nil}
      unconditional_rule = %{predicates: [], to: nil, via: nil}

      for rules <- [
            [conditional_rule, unconditional_rule],
            [unconditional_rule, conditional_rule]
          ] do
        assert %{params: placeholders, sql: sql} =
                 compile(term, mapping, %{rules: rules})

        assert placeholders == [value: true]
        assert String.contains?(sql, ~s|WHERE "a" = $1 ORDER BY|)
      end
    end

    test "composes the included type's read policy into the include subquery, keyed on its alias" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])

      term =
        PolicyModule1
        |> include(parent)
        |> Stage.normalize()

      rules = [%{predicates: [], to: nil, via: nil}]

      assert %{sql: sql} = compile(term, mapping, %{rules: rules})

      assert String.contains?(
               sql,
               ~s|WHERE "$i1"."id" = "test_fixtures_policy_module1"."parent_id" | <>
                 ~s|AND EXISTS (SELECT 1 FROM "hologram_data"."hologram_role_grant" AS "$rg" | <>
                 ~s|WHERE "$rg"."user_id" = $1 | <>
                 ~s|AND "$rg"."role" = ANY($2::"hologram_data"."hologram_role_grant_role_$enum"[]) | <>
                 ~s|AND "$rg"."entity_type" = | <>
                 ~s|$3::"hologram_data"."hologram_role_grant_entity_type_$enum" | <>
                 ~s|AND ("$rg"."entity_id" = "$i1"."id" OR "$rg"."entity_id" IS NULL))|
             )
    end

    test "leaves include subqueries unfiltered without a policy" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])

      term =
        PolicyModule1
        |> include(parent)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|WHERE "$i1"."id" = "test_fixtures_policy_module1"."parent_id")|
             )
    end

    test "denies everything for a policy with no rules" do
      mapping = Mapper.derive!([Module2], [])
      term = Stage.normalize(Module2)

      assert %{params: [], sql: sql} =
               compile(term, mapping, %{rules: []})

      assert String.contains?(sql, " WHERE FALSE ORDER BY")
    end

    test "binds one reserved slot for every actor reference" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])
      term = Stage.normalize(Module3)

      rules = [
        %{predicates: [{:b_id, :==, {:actor}}], to: nil, via: nil},
        %{predicates: [{:c_id, :==, {:actor}}], to: nil, via: nil}
      ]

      assert %{params: [:actor], sql: sql} =
               compile(term, mapping, %{rules: rules})

      assert String.contains?(sql, ~s|WHERE (("b_id" = $1) OR ("c_id" = $1))|)
    end

    test "allocates the actor slot after the authored placeholders" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term = %{Stage.normalize(Module3) | filter: [{:c_id, :==, {:placeholder, :target}}]}

      rules = [%{predicates: [{:b_id, :==, {:actor}}], to: nil, via: nil}]

      assert %{params: [{:placeholder, :target, :uuid}, :actor], sql: sql} =
               compile(term, mapping, %{rules: rules})

      assert String.contains?(sql, ~s|WHERE "c_id" = $1 AND "b_id" = $2|)
    end

    test "composes a policy into a counting query before aggregation" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> Query.count()
        |> Stage.normalize()

      rules = [%{predicates: [{:a, :==, true}], to: nil, via: nil}]

      assert compile(term, mapping, %{rules: rules}) == %{
               params: [{:value, true}],
               sql:
                 ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_entity_module2" | <>
                   ~s|WHERE "a" = $1|
             }
    end

    test "composes an own-roles grant reference as an EXISTS over the grant store" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])
      term = Stage.normalize(PolicyModule1)

      rules = [%{predicates: [], to: [{:own, [:editor, :owner]}], via: nil}]

      assert compile(term, mapping, %{rules: rules}) == %{
               params: [
                 :actor,
                 {:value, ["editor", "owner"]},
                 {:value, "Hologram.Test.Fixtures.Policy.Module1"}
               ],
               sql:
                 ~s|SELECT "id", "priority", "public", "author_id", "parent_id", | <>
                   ~s|"created_at", "updated_at", "$revisions" | <>
                   ~s|FROM "hologram_data"."test_fixtures_policy_module1" | <>
                   ~s|WHERE EXISTS (SELECT 1 FROM "hologram_data"."hologram_role_grant" AS "$rg" | <>
                   ~s|WHERE "$rg"."user_id" = $1 | <>
                   ~s|AND "$rg"."role" = ANY($2::"hologram_data"."hologram_role_grant_role_$enum"[]) | <>
                   ~s|AND "$rg"."entity_type" = | <>
                   ~s|$3::"hologram_data"."hologram_role_grant_entity_type_$enum" | <>
                   ~s|AND ("$rg"."entity_id" = "test_fixtures_policy_module1"."id" | <>
                   ~s|OR "$rg"."entity_id" IS NULL)) ORDER BY "id" ASC|
             }
    end

    test "composes a global grant reference as an uncorrelated grant-store lookup" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])
      term = Stage.normalize(PolicyModule2)

      rules = [%{predicates: [], to: [{:global, [Role.Module1, Role.Module2]}], via: nil}]

      assert compile(term, mapping, %{rules: rules}) == %{
               params: [
                 :actor,
                 {:value,
                  ["Hologram.Test.Fixtures.Role.Module1", "Hologram.Test.Fixtures.Role.Module2"]}
               ],
               sql:
                 ~s|SELECT "id", "public", "created_at", "updated_at", "$revisions" | <>
                   ~s|FROM "hologram_data"."test_fixtures_policy_module2" | <>
                   ~s|WHERE EXISTS (SELECT 1 FROM "hologram_data"."hologram_role_grant" AS "$rg" | <>
                   ~s|WHERE "$rg"."user_id" = $1 | <>
                   ~s|AND "$rg"."role" = ANY($2::"hologram_data"."hologram_role_grant_role_$enum"[]) | <>
                   ~s|AND "$rg"."entity_type" IS NULL AND "$rg"."entity_id" IS NULL) | <>
                   ~s|ORDER BY "id" ASC|
             }
    end

    test "elides a global grant reference for an anonymous session" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])
      term = Stage.normalize(PolicyModule2)

      rules = [%{predicates: [], to: [{:global, [Role.Module1]}], via: nil}]

      assert %{params: placeholders, sql: sql} =
               compile(term, mapping, %{anonymous?: true, rules: rules})

      assert placeholders == []
      refute String.contains?(sql, "hologram_role_grant")
    end

    test "composes a namespaced grant reference as a type-wide lookup" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])
      term = Stage.normalize(PolicyModule1)

      rules = [%{predicates: [], to: [{:type, PolicyModule2, [:admin]}], via: nil}]

      assert %{params: placeholders, sql: sql} =
               compile(term, mapping, %{rules: rules})

      assert placeholders == [
               :actor,
               {:value, ["admin"]},
               {:value, "Hologram.Test.Fixtures.Policy.Module2"}
             ]

      assert String.contains?(
               sql,
               ~s|AND "$rg"."entity_type" = $3::"hologram_data"."hologram_role_grant_entity_type_$enum" | <>
                 ~s|AND "$rg"."entity_id" IS NULL)|
             )
    end

    test "composes a relationship grant reference against the reference column" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])
      term = Stage.normalize(PolicyModule1)

      rules = [%{predicates: [], to: [{:rel, [:parent], [:admin]}], via: nil}]

      assert %{params: placeholders, sql: sql} =
               compile(term, mapping, %{rules: rules})

      assert placeholders == [
               :actor,
               {:value, ["admin"]},
               {:value, "Hologram.Test.Fixtures.Policy.Module2"}
             ]

      assert String.contains?(
               sql,
               ~s|AND "$rg"."entity_id" = "test_fixtures_policy_module1"."parent_id")|
             )
    end

    # The role is held on the row the chain ends at, whose id the last reference holds - read off
    # the row before it, raw, the way a policy reads the rows it is followed through.
    test "composes a relationship grant reference two hops away through a scalar subquery" do
      mapping =
        Mapper.derive!(
          [Module14, PolicyModule1, PolicyModule2, PolicyModule5, PolicyModule8, RoleGrant],
          []
        )

      term = Stage.normalize(PolicyModule8)

      rules = [%{predicates: [], to: [{:rel, [:parent, :parent], [:viewer]}], via: nil}]

      assert %{params: placeholders, sql: sql} =
               compile(term, mapping, %{rules: rules})

      assert placeholders == [
               :actor,
               {:value, ["viewer"]},
               {:value, "Hologram.Test.Fixtures.Policy.Module1"}
             ]

      target_id_sql =
        hop(
          1,
          PolicyModule5,
          ~s|"$p1"."parent_id"|,
          ~s|"test_fixtures_policy_module8"."parent_id"|
        )

      assert String.contains?(sql, ~s|AND "$rg"."entity_id" = #{target_id_sql})|)
    end

    test "composes grant references and predicates as one conjunction" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])
      term = Stage.normalize(PolicyModule1)

      rules = [%{predicates: [{:priority, :>=, 3}], to: [{:own, [:editor]}], via: nil}]

      assert %{sql: sql} = compile(term, mapping, %{rules: rules})

      assert String.contains?(sql, ~s|WHERE "priority" >= $1 AND EXISTS (SELECT 1|)
    end

    test "composes several grant references of one rule as an OR group" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])
      term = Stage.normalize(PolicyModule1)

      rules = [
        %{predicates: [], to: [{:own, [:viewer]}, {:type, PolicyModule2, [:admin]}], via: nil}
      ]

      assert %{sql: sql} = compile(term, mapping, %{rules: rules})

      assert String.contains?(sql, ~s|WHERE ((EXISTS (SELECT 1|)
      assert String.contains?(sql, ~s|) OR (EXISTS (SELECT 1|)
    end

    test "composes a delegation as an EXISTS over the related entity's policy" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])
      term = Stage.normalize(PolicyModule1)

      rules = [%{predicates: [], to: nil, via: {:publish, [:parent]}}]

      assert compile(term, mapping, %{rules: rules}) == %{
               params: [{:value, true}],
               sql:
                 ~s|SELECT "id", "priority", "public", "author_id", "parent_id", | <>
                   ~s|"created_at", "updated_at", "$revisions" | <>
                   ~s|FROM "hologram_data"."test_fixtures_policy_module1" | <>
                   ~s|WHERE EXISTS (SELECT 1 FROM "hologram_data"."test_fixtures_policy_module2" | <>
                   ~s|AS "$d1" WHERE "$d1"."id" = "test_fixtures_policy_module1"."parent_id" | <>
                   ~s|AND "public" = $1) ORDER BY "id" ASC|
             }
    end

    test "composes a delegation two hops away, joined through a scalar subquery" do
      mapping =
        Mapper.derive!(
          [Module14, PolicyModule1, PolicyModule2, PolicyModule5, PolicyModule8, RoleGrant],
          []
        )

      term = Stage.normalize(PolicyModule8)

      rules = [%{predicates: [], to: nil, via: {:publish, [:parent, :parent]}}]

      target_id_sql =
        hop(
          1,
          PolicyModule5,
          ~s|"$p1"."parent_id"|,
          ~s|"test_fixtures_policy_module8"."parent_id"|
        )

      assert compile(term, mapping, %{rules: rules}) == %{
               params: [{:value, true}],
               sql:
                 ~s|SELECT "id", "parent_id", "created_at", "updated_at", "$revisions" | <>
                   ~s|FROM "hologram_data"."test_fixtures_policy_module8" | <>
                   ~s|WHERE EXISTS (SELECT 1 FROM "hologram_data"."test_fixtures_policy_module1" | <>
                   ~s|AS "$d1" WHERE "$d1"."id" = #{target_id_sql} | <>
                   ~s|AND EXISTS (SELECT 1 FROM "hologram_data"."test_fixtures_policy_module2" | <>
                   ~s|AS "$d2" WHERE "$d2"."id" = "$d1"."parent_id" AND "public" = $1)) | <>
                   ~s|ORDER BY "id" ASC|
             }
    end

    # The related row is a row of the delegating type, so only the alias keeps the two apart - the
    # table name inside the subquery would name the inner row on both sides of the join.
    test "composes a delegation back to the delegating entity type under an alias of its own" do
      mapping = Mapper.derive!([PolicyModule9], [])
      term = Stage.normalize(PolicyModule9)
      rules = Policy.build(PolicyModule9)[:read]

      assert compile(term, mapping, %{rules: rules}) == %{
               params: [{:value, false}],
               sql:
                 ~s|SELECT "id", "archived", "parent_id", "created_at", "updated_at", "$revisions" | <>
                   ~s|FROM "hologram_data"."test_fixtures_policy_module9" | <>
                   ~s|WHERE EXISTS (SELECT 1 FROM "hologram_data"."test_fixtures_policy_module9" | <>
                   ~s|AS "$d1" WHERE "$d1"."id" = "test_fixtures_policy_module9"."parent_id" | <>
                   ~s|AND "archived" = $1) ORDER BY "id" ASC|
             }
    end

    # The mapper strips the app root, so this type's table is a bare d1 - the name the delegation's
    # alias would have without its $, which would put both sides of the join on the inner row.
    test "keeps a delegation's alias apart from a table of the same name" do
      defmodule Elixir.Hologram.D1 do
        use Hologram.Entity

        attribute :archived, :boolean, default: false

        relationship :parent, Hologram.D1, optional: true

        allow :read, via: {:update, parent}
        allow :update, when: archived == false
      end

      mapping = Mapper.derive!([Hologram.D1], [])
      term = Stage.normalize(Hologram.D1)
      rules = Policy.build(Hologram.D1)[:read]

      assert compile(term, mapping, %{rules: rules}) == %{
               params: [{:value, false}],
               sql:
                 ~s|SELECT "id", "archived", "parent_id", "created_at", "updated_at", "$revisions" | <>
                   ~s|FROM "hologram_data"."d1" | <>
                   ~s|WHERE EXISTS (SELECT 1 FROM "hologram_data"."d1" AS "$d1" | <>
                   ~s|WHERE "$d1"."id" = "d1"."parent_id" AND "archived" = $1) | <>
                   ~s|ORDER BY "id" ASC|
             }
    end

    test "gives each nested delegation an alias of its own" do
      mapping =
        Mapper.derive!(
          [Module14, PolicyModule1, PolicyModule2, PolicyModule5, PolicyModule8, RoleGrant],
          []
        )

      term = Stage.normalize(PolicyModule8)
      rules = Policy.build(PolicyModule8)[:read]

      assert compile(term, mapping, %{anonymous?: true, rules: rules}) == %{
               params: [{:value, true}],
               sql:
                 ~s|SELECT "id", "parent_id", "created_at", "updated_at", "$revisions" | <>
                   ~s|FROM "hologram_data"."test_fixtures_policy_module8" | <>
                   ~s|WHERE EXISTS (SELECT 1 FROM "hologram_data"."test_fixtures_policy_module5" | <>
                   ~s|AS "$d1" WHERE "$d1"."id" = "test_fixtures_policy_module8"."parent_id" | <>
                   ~s|AND EXISTS (SELECT 1 FROM "hologram_data"."test_fixtures_policy_module1" | <>
                   ~s|AS "$d2" WHERE "$d2"."id" = "$d1"."parent_id" AND "public" = $1)) | <>
                   ~s|ORDER BY "id" ASC|
             }
    end

    # The included row is the delegating one there, so the delegation correlates on the include's
    # alias rather than on the statement's table.
    test "composes a delegation inside an include subquery against the include's alias" do
      mapping = Mapper.derive!([PolicyModule9], [])

      term =
        PolicyModule9
        |> include(parent)
        |> Stage.normalize()

      rules = Policy.build(PolicyModule9)[:read]

      assert compile(term, mapping, %{rules: rules}) == %{
               params: [{:value, false}, {:value, false}],
               sql:
                 ~s|SELECT "id", "archived", "parent_id", "created_at", "updated_at", "$revisions", | <>
                   ~s|(SELECT jsonb_build_object('id', "$i1"."id", 'archived', "$i1"."archived", | <>
                   ~s|'parent_id', "$i1"."parent_id", 'created_at', "$i1"."created_at", | <>
                   ~s|'updated_at', "$i1"."updated_at", '$revisions', "$i1"."$revisions") | <>
                   ~s|FROM "hologram_data"."test_fixtures_policy_module9" AS "$i1" | <>
                   ~s|WHERE "$i1"."id" = "test_fixtures_policy_module9"."parent_id" | <>
                   ~s|AND EXISTS (SELECT 1 FROM "hologram_data"."test_fixtures_policy_module9" | <>
                   ~s|AS "$d1" WHERE "$d1"."id" = "$i1"."parent_id" AND "archived" = $1)) | <>
                   ~s|AS "parent" FROM "hologram_data"."test_fixtures_policy_module9" | <>
                   ~s|WHERE EXISTS (SELECT 1 FROM "hologram_data"."test_fixtures_policy_module9" | <>
                   ~s|AS "$d1" WHERE "$d1"."id" = "test_fixtures_policy_module9"."parent_id" | <>
                   ~s|AND "archived" = $2) ORDER BY "id" ASC|
             }
    end

    test "denies a delegation to an operation the related entity type does not grant" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])
      term = Stage.normalize(PolicyModule1)

      rules = [%{predicates: [], to: nil, via: {:delete, [:parent]}}]

      assert %{sql: sql} = compile(term, mapping, %{rules: rules})

      assert String.contains?(
               sql,
               ~s|"test_fixtures_policy_module1"."parent_id" AND FALSE)|
             )
    end

    test "composes a delegation alongside the rule's own predicates" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])
      term = Stage.normalize(PolicyModule1)

      rules = [%{predicates: [{:priority, :>=, 3}], to: nil, via: {:publish, [:parent]}}]

      assert %{params: placeholders, sql: sql} =
               compile(term, mapping, %{rules: rules})

      assert placeholders == [{:value, 3}, {:value, true}]
      assert String.contains?(sql, ~s|WHERE "priority" >= $1 AND EXISTS (SELECT 1|)
    end

    test "composes the delegated policy's grant references with the shared actor slot" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])
      term = Stage.normalize(PolicyModule1)

      rules = [
        %{predicates: [], to: [{:own, [:owner]}], via: nil},
        %{predicates: [], to: nil, via: {:read, [:parent]}}
      ]

      assert %{params: placeholders, sql: sql} =
               compile(term, mapping, %{rules: rules})

      assert Enum.count(placeholders, &(&1 == :actor)) == 1

      assert String.contains?(
               sql,
               ~s|EXISTS (SELECT 1 FROM "hologram_data"."test_fixtures_policy_module2" | <>
                 ~s|AS "$d1" WHERE "$d1"."id" = "test_fixtures_policy_module1"."parent_id" | <>
                 ~s|AND EXISTS (SELECT 1 FROM "hologram_data"."hologram_role_grant" AS "$rg" | <>
                 ~s|WHERE "$rg"."user_id" = $1 | <>
                 ~s|AND "$rg"."role" = ANY($4::"hologram_data"."hologram_role_grant_role_$enum"[]) | <>
                 ~s|AND "$rg"."entity_type" = | <>
                 ~s|$5::"hologram_data"."hologram_role_grant_entity_type_$enum" | <>
                 ~s|AND ("$rg"."entity_id" = "$d1"."id" OR "$rg"."entity_id" IS NULL))|
             )
    end

    test "composes the grant store's own visibility policy" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])
      term = Stage.normalize(RoleGrant)
      policy = %{rules: Policy.build(RoleGrant)[:read]}

      assert %{params: placeholders, sql: sql} = compile(term, mapping, policy)

      assert placeholders == [
               :actor,
               {:value, "Hologram.Test.Fixtures.Policy.Module1"},
               {:value, ["owner"]},
               {:value, "Hologram.Test.Fixtures.Policy.Module1"},
               {:value, "Hologram.Test.Fixtures.Policy.Module2"},
               {:value, ["admin", "member"]},
               {:value, "Hologram.Test.Fixtures.Policy.Module2"},
               {:value,
                ["Hologram.Test.Fixtures.Role.Module1", "Hologram.Test.Fixtures.Role.Module2"]}
             ]

      assert String.contains?(sql, ~s|WHERE (("user_id" = $1)|)

      assert String.contains?(
               sql,
               ~s|("entity_type" = $2 AND EXISTS (SELECT 1 FROM | <>
                 ~s|"hologram_data"."hologram_role_grant" AS "$rg" WHERE "$rg"."user_id" = $1 | <>
                 ~s|AND "$rg"."role" = ANY($3::"hologram_data"."hologram_role_grant_role_$enum"[]) | <>
                 ~s|AND "$rg"."entity_type" = | <>
                 ~s|$4::"hologram_data"."hologram_role_grant_entity_type_$enum" | <>
                 ~s|AND "$rg"."entity_id" = "hologram_role_grant"."entity_id"))|
             )
    end

    test "binds the placeholders of a disjunction in reading order" do
      mapping = Mapper.derive!([Module2], [])

      term = %{
        Stage.normalize(Module2)
        | filter: [{:or, [[{:a, :==, {:placeholder, :x}}], [{:b, :==, {:placeholder, :y}}]]}]
      }

      assert %{params: params, sql: sql} = compile(term, mapping)

      assert params == [{:placeholder, :x, :boolean}, {:placeholder, :y, :integer}]
      assert String.contains?(sql, ~s|WHERE (("a" = $1) OR ("b" = $2)) ORDER BY|)
    end

    test "compiles a disjunction as an OR group of its alternatives" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(a == true or (b >= 3 and c == "x"))
        |> Stage.normalize()

      assert compile(term, mapping) == %{
               params: [{:value, true}, {:value, 3}, {:value, "x"}],
               sql:
                 ~s(SELECT "id", "a", "b", "c", "created_at", "updated_at", "$revisions", "c_$sort" ) <>
                   ~s(FROM "hologram_data"."test_fixtures_entity_module2" ) <>
                   ~s|WHERE (("a" = $1) OR ("b" >= $2 AND "c" = $3)) ORDER BY "id" ASC|
             }
    end

    test "compiles a disjunction before the conjuncts beside it" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(a: true)
        |> filter(b == 1 or c == "x")
        |> Stage.normalize()

      assert %{params: [{:value, 1}, {:value, "x"}, {:value, true}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(sql, ~s|WHERE (("b" = $1) OR ("c" = $2)) AND "a" = $3 ORDER BY|)
    end

    # The grouped alternative holds a disjunction, a two-element tuple that sorts ahead of every
    # predicate, so it renders first, and its alternative renders ahead of a == true.
    test "compiles a nested disjunction inside an alternative" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(a == true or (b >= 3 and (c == "x" or c == "y")))
        |> Stage.normalize()

      assert %{params: params, sql: sql} = compile(term, mapping)

      assert params == [{:value, "x"}, {:value, "y"}, {:value, 3}, {:value, true}]

      assert String.contains?(
               sql,
               ~s|WHERE (((("c" = $1) OR ("c" = $2)) AND "b" >= $3) OR ("a" = $4)) ORDER BY|
             )
    end

    test "keeps a disjunction inside a to-many include's filter" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term =
        Module3
        |> include(a, &filter(&1, a == true or c == "x"))
        |> Stage.normalize()

      assert %{params: [{:value, true}, {:value, "x"}], sql: sql} = compile(term, mapping)

      assert String.contains?(sql, ~s| AND (("a" = $1) OR ("c" = $2)) ORDER BY "id" ASC|)
    end

    test "compiles inequality null-inclusively on optional attributes" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(b != 3)
        |> Stage.normalize()

      assert %{params: [{:value, 3}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE ("b" != $1 OR "b" IS NULL)|)
    end

    test "compiles inequality plainly on required attributes" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(a != false)
        |> Stage.normalize()

      assert %{params: [{:value, false}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "a" != $1))
    end

    test "compiles limit and offset as literal bounds" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> limit(50)
        |> offset(20)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( ORDER BY "id" ASC LIMIT 50 OFFSET 20))
    end

    test "compiles membership as an array binding" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(c in ["x", "y"])
        |> Stage.normalize()

      assert %{params: [{:value, ["x", "y"]}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE "c" = ANY($1)|)
    end

    test "compiles negated membership null-inclusively on optional attributes" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(b not in [1, 2])
        |> Stage.normalize()

      assert %{params: [{:value, [1, 2]}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE ("b" != ALL($1) OR "b" IS NULL)|)
    end

    test "compiles nil-holding membership into the IS NULL branch" do
      mapping = Mapper.derive!([Module2], [])
      term = %{Stage.normalize(Module2) | filter: [{:b, :in, [nil, 1]}]}

      assert %{params: [{:value, [1]}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE ("b" = ANY($1) OR "b" IS NULL)|)
    end

    test "compiles nil-holding negated membership into the value-requiring branch" do
      mapping = Mapper.derive!([Module2], [])
      term = %{Stage.normalize(Module2) | filter: [{:b, :not_in, [nil, 1]}]}

      assert %{params: [{:value, [1]}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE ("b" != ALL($1) AND "b" IS NOT NULL)|)
    end

    test "compiles nil-only membership as IS NULL without a bind slot" do
      mapping = Mapper.derive!([Module2], [])
      term = %{Stage.normalize(Module2) | filter: [{:b, :in, [nil]}]}

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "b" IS NULL))
    end

    test "compiles nil-only negated membership as IS NOT NULL without a bind slot" do
      mapping = Mapper.derive!([Module2], [])
      term = %{Stage.normalize(Module2) | filter: [{:b, :not_in, [nil]}]}

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "b" IS NOT NULL))
    end

    test "aliases sibling includes distinctly" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term =
        Module3
        |> include(b)
        |> include(c)
        |> Stage.normalize()

      assert %{sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|FROM "hologram_data"."test_fixtures_entity_module2" AS "$i1" WHERE "$i1"."id" = "test_fixtures_entity_module3"."b_id") AS "b"|
             )

      assert String.contains?(
               sql,
               ~s|FROM "hologram_data"."test_fixtures_entity_module1" AS "$i2" WHERE "$i2"."id" = "test_fixtures_entity_module3"."c_id") AS "c"|
             )
    end

    test "compiles counting queries as a bare count" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(a: true)
        |> count()
        |> Stage.normalize()

      assert compile(term, mapping) == %{
               params: [{:value, true}],
               sql:
                 ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_entity_module2" WHERE "a" = $1|
             }
    end

    test "compiles counting over view bounds as a capped subquery" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> limit(50)
        |> count()
        |> Stage.normalize()

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s|SELECT count(*) FROM (SELECT 1 FROM "hologram_data"."test_fixtures_entity_module2" LIMIT 50) AS "sub"|
             }
    end

    test "embeds a to-many relationship as an aggregated array" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term =
        Module3
        |> include(a)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)

      expected_fragment =
        ~s|(SELECT COALESCE(jsonb_agg(jsonb_build_object(| <>
          ~s|'id', "$i1"."id", 'a', "$i1"."a", 'b', "$i1"."b", 'c', "$i1"."c", | <>
          ~s|'created_at', "$i1"."created_at", 'updated_at', "$i1"."updated_at", '$revisions', "$i1"."$revisions", | <>
          ~s|'c_$sort', "$i1"."c_$sort"| <>
          ~s|) ORDER BY "$i1"."id" ASC), '[]'::jsonb) | <>
          ~s|FROM (SELECT "$t1".* | <>
          ~s|FROM "hologram_data"."test_fixtures_entity_module2" AS "$t1" | <>
          ~s|WHERE "$t1"."id" IN (SELECT "$j1"."target_id" | <>
          ~s|FROM "hologram_data"."test_fixtures_entity_module3_a_$join" AS "$j1" | <>
          ~s|WHERE "$j1"."source_id" = "test_fixtures_entity_module3"."id") | <>
          ~s|ORDER BY "id" ASC) AS "$i1") AS "a"|

      assert String.contains?(sql, expected_fragment)
    end

    test "embeds a to-one relationship as a jsonb subselect" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term =
        Module3
        |> include(c)
        |> Stage.normalize()

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s|SELECT "id", "b_id", "c_id", "created_at", "updated_at", "$revisions", | <>
                   ~s|(SELECT jsonb_build_object('id', "$i1"."id", 'created_at', "$i1"."created_at", 'updated_at', "$i1"."updated_at", '$revisions', "$i1"."$revisions") | <>
                   ~s|FROM "hologram_data"."test_fixtures_entity_module1" AS "$i1" | <>
                   ~s|WHERE "$i1"."id" = "test_fixtures_entity_module3"."c_id") AS "c" | <>
                   ~s|FROM "hologram_data"."test_fixtures_entity_module3" ORDER BY "id" ASC|
             }
    end

    test "embeds a self-referencing to-one unambiguously" do
      mapping = Mapper.derive!([Module3, Module5], [])

      term =
        Module5
        |> include(b)
        |> Stage.normalize()

      assert %{sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|FROM "hologram_data"."test_fixtures_entity_module5" AS "$i1" WHERE "$i1"."id" = "test_fixtures_entity_module5"."b_id") AS "b"|
             )
    end

    test "compiles nil equality as IS NULL without a bind slot" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(b: nil)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "b" IS NULL))
    end

    test "compiles nil inequality as IS NOT NULL without a bind slot" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(b != nil)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "b" IS NOT NULL))
    end

    test "compiles ordering comparisons null-exclusively" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(b >= 3 and b < 10)
        |> Stage.normalize()

      assert %{params: [{:value, 10}, {:value, 3}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "b" < $1 AND "b" >= $2))
    end

    test "compiles single-result queries with a unit limit" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(a: true)
        |> one()
        |> Stage.normalize()

      assert %{params: [{:value, true}], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( WHERE "a" = $1 ORDER BY "id" ASC LIMIT 1))
    end

    test "compiles ordering keys with directions and the id tiebreaker" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> order_by(b: :desc, c: :asc)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( ORDER BY "b" DESC, "c_$sort" ASC, "c" ASC, "id" ASC))
    end

    # A bound is a position in the list the attribute sorts into, so it compares by the same pair
    # ORDER BY sorts by - the key carries the order, the value settles what the key cannot.
    test "compiles a string comparison through the sort-key companion" do
      mapping = Mapper.derive!([Module2], [])
      term = %{Stage.normalize(Module2) | filter: [{:c, :>=, "Zoe"}]}

      assert %{params: [{:value, "zoe"}, {:value, "Zoe"}], sql: sql} = compile(term, mapping)

      assert String.contains?(sql, ~s|WHERE ("c_$sort", "c") >= ($1, $2)|)
    end

    test "binds a placeholder compared against a string as a key slot and a value slot" do
      mapping = Mapper.derive!([Module2], [])
      term = %{Stage.normalize(Module2) | filter: [{:c, :>=, {:placeholder, :min}}]}

      assert %{
               params: [{:placeholder, :min, :sort_key}, {:placeholder, :min, :string}],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(sql, ~s|WHERE ("c_$sort", "c") >= ($1, $2)|)
    end

    test "compares a string inside an include through the include's companion" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term =
        Module3
        |> include(a, fn related_query -> filter(related_query, c >= "Zoe") end)
        |> Stage.normalize()

      assert %{params: [{:value, "zoe"}, {:value, "Zoe"}], sql: sql} = compile(term, mapping)

      assert String.contains?(sql, ~s|AND ("c_$sort", "c") >= ($1, $2)|)
    end

    # Nil is a value to equality, so the DISTINCT form - = would be unknown over a NULL.
    test "compiles an attribute equality as IS NOT DISTINCT FROM" do
      mapping = Mapper.derive!([Module10], [])

      term =
        Module10
        |> filter(count == priority)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "count" IS NOT DISTINCT FROM "priority" ))
    end

    test "compiles an attribute inequality as IS DISTINCT FROM" do
      mapping = Mapper.derive!([Module10], [])

      term =
        Module10
        |> filter(count != priority)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "count" IS DISTINCT FROM "priority" ))
    end

    test "compiles an ordering comparison between attributes as a column comparison" do
      mapping = Mapper.derive!([Module10], [])

      term =
        Module10
        |> filter(count > priority)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "count" > "priority" ))
    end

    test "compiles an integer compared with a float as a column comparison" do
      mapping = Mapper.derive!([Module10], [])

      term =
        Module10
        |> filter(count < rating)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "count" < "rating" ))
    end

    test "compiles a string pair through both sort-key companions" do
      mapping = Mapper.derive!([Module10], [])

      term =
        Module10
        |> filter(username < bio)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|WHERE ("username_$sort", "username") < ("bio_$sort", "bio")|
             )
    end

    # Each enum attribute is its own type, and Postgres compares no two of them.
    test "casts an enum operand to the compared attribute's type" do
      mapping = Mapper.derive!([Module24], [])

      term =
        Module24
        |> filter(level < priority)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|WHERE "level" < "priority"::text::"hologram_data"."test_fixtures_entity_module24_level_$enum"|
             )
    end

    test "casts an enum operand under equality" do
      mapping = Mapper.derive!([Module24], [])

      term =
        Module24
        |> filter(level == priority)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|WHERE "level" IS NOT DISTINCT FROM "priority"::text::"hologram_data"."test_fixtures_entity_module24_level_$enum"|
             )
    end

    test "binds no slot for an attribute operand beside a placeholder" do
      mapping = Mapper.derive!([Module10], [])

      term = %{
        Stage.normalize(Module10)
        | filter: [{:count, :<, {:attribute, :priority}}, {:username, :==, {:placeholder, :name}}]
      }

      assert %{params: [{:placeholder, :name, :string}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "count" < "priority" AND "username" = $1 ))
    end

    test "composes a policy rule comparing two attributes" do
      mapping = Mapper.derive!([Module10], [])
      term = Stage.normalize(Module10)
      rules = [%{predicates: [{:count, :<=, {:attribute, :priority}}], to: nil, via: nil}]

      assert %{params: [], sql: sql} = compile(term, mapping, %{rules: rules})
      assert String.contains?(sql, ~s( WHERE "count" <= "priority" ))
    end

    test "compiles string ordering through the sort-key companion" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> order_by(c: :desc)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( ORDER BY "c_$sort" DESC, "c" DESC, "id" ASC))
    end

    test "compiles single-result queries with a zero limit as zero" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> limit(0)
        |> one()
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( ORDER BY "id" ASC LIMIT 0))
    end

    test "encodes literal values with the attribute's codec type" do
      mapping = Mapper.derive!([Module4], [])

      term =
        Module4
        |> filter(c: :x)
        |> Stage.normalize()

      assert %{params: [{:value, "x"}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "c" = $1))
    end

    test "mixes literal and placeholder bindings in placeholder order" do
      mapping = Mapper.derive!([Module2], [])

      term = %{
        Stage.normalize(Module2)
        | filter: [{:a, :==, true}, {:c, :==, {:placeholder, :search}}]
      }

      assert %{
               params: [{:value, true}, {:placeholder, :search, :string}],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(sql, ~s( WHERE "a" = $1 AND "c" = $2))
    end

    test "nests a to-one inside a to-one include" do
      mapping = Mapper.derive!([Module2, Module3, Module5], [])

      term =
        Module5
        |> include(a.b)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)

      expected_fragment =
        ~s|, 'b', (SELECT jsonb_build_object(| <>
          ~s|'id', "$i2"."id", 'a', "$i2"."a", 'b', "$i2"."b", 'c', "$i2"."c", | <>
          ~s|'created_at', "$i2"."created_at", 'updated_at', "$i2"."updated_at", '$revisions', "$i2"."$revisions", | <>
          ~s|'c_$sort', "$i2"."c_$sort"| <>
          ~s|) FROM "hologram_data"."test_fixtures_entity_module2" AS "$i2" | <>
          ~s|WHERE "$i2"."id" = "$i1"."b_id")|

      assert String.contains?(sql, expected_fragment)
    end

    test "nests an include inside a to-many aggregation" do
      mapping = Mapper.derive!([Module2, Module3, Module6], [])

      term =
        Module6
        |> include(a.b)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|, 'b', (SELECT jsonb_build_object('id', "$i2"."id"|
             )

      assert String.contains?(sql, ~s|AS "$i2" WHERE "$i2"."id" = "$i1"."b_id")|)

      assert String.contains?(
               sql,
               ~s|FROM "hologram_data"."test_fixtures_entity_module6_a_$join" AS "$j1"|
             )
    end

    test "omits includes from counting queries" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term =
        Module3
        |> include(c)
        |> count()
        |> Stage.normalize()

      assert compile(term, mapping) == %{
               params: [],
               sql: ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_entity_module3"|
             }
    end

    test "selects the mapped columns in physical order" do
      mapping = Mapper.derive!([Module2], [])
      term = Stage.normalize(Module2)

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s(SELECT "id", "a", "b", "c", "created_at", "updated_at", "$revisions", "c_$sort" FROM "hologram_data"."test_fixtures_entity_module2" ORDER BY "id" ASC)
             }
    end

    test "selects reference columns for to-one relationships" do
      mapping = Mapper.derive!([Module2, Module3], [])
      term = Stage.normalize(Module3)

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s(SELECT "id", "b_id", "c_id", "created_at", "updated_at", "$revisions" FROM "hologram_data"."test_fixtures_entity_module3" ORDER BY "id" ASC)
             }
    end

    test "threads include placeholders after the root's" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      base_term =
        Module3
        |> include(a, &filter(&1, a: true))
        |> Stage.normalize()

      term = %{base_term | filter: [{:id, :==, {:placeholder, :root_id}}]}

      assert %{params: [{:placeholder, :root_id, :uuid}, {:value, true}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(sql, ~s( WHERE "id" = $1))
      assert String.contains?(sql, ~s( AND "a" = $2))
    end
  end

  describe "compile/2 - paths" do
    # Shared by several tests, so defined once here rather than inside the first test reaching them -
    # tests run in any order.
    defmodule PathTarget1 do
      use Hologram.Entity

      attribute :name, :string
      attribute :public, :boolean, default: false

      allow :read, when: public == true
    end

    defmodule PathSource1 do
      use Hologram.Entity

      relationship :target, PathTarget1, optional: true

      allow :read
    end

    defmodule PathTarget2 do
      use Hologram.Entity

      attribute :name, :string

      relationship :owner, Module14, optional: true

      allow :read, when: owner_id == user_id()
    end

    defmodule PathSource2 do
      use Hologram.Entity

      relationship :target, PathTarget2, optional: true

      allow :read
    end

    defmodule PathMiddle3 do
      use Hologram.Entity

      relationship :target, PathTarget1, optional: true

      allow :read, when: target.public == true
    end

    defmodule PathSource3 do
      use Hologram.Entity

      relationship :middle, PathMiddle3, optional: true

      allow :read, via: middle
    end

    defmodule PathSource4 do
      use Hologram.Entity

      relationship :middle, PathMiddle3, optional: true

      allow :read
    end

    test "compiles a one-hop path to a scalar subquery" do
      mapping = path_mapping([Module1, Module2, Module3])
      term = path_term(Module3, [{[:b, :a], true}])

      b_a = hop(1, Module2, ~s("$p1"."a"), ~s("test_fixtures_entity_module3"."b_id"))

      assert compile(term, mapping) == %{
               params: [{:value, true}],
               sql:
                 ~s(SELECT "id", "b_id", "c_id", "created_at", "updated_at", "$revisions" ) <>
                   ~s(FROM "hologram_data"."test_fixtures_entity_module3" ) <>
                   ~s(WHERE #{b_a} = $1 ORDER BY "id" ASC)
             }
    end

    test "nests a hop inside the one before it" do
      mapping = path_mapping([Module1, Module2, Module3, Module5])
      term = path_term(Module5, [{[:a, :b, :c], "x"}])

      a_b_c =
        hop(
          1,
          Module3,
          hop(2, Module2, ~s("$p2"."c"), ~s("$p1"."b_id")),
          ~s("test_fixtures_entity_module5"."a_id")
        )

      assert %{params: [{:value, "x"}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE #{a_b_c} = $1 ORDER BY))
    end

    test "compiles a path operand" do
      mapping = path_mapping([Module1, Module2, Module3])
      term = path_term(Module3, c_id: {:attribute, [:b, :id]})

      b_id = hop(1, Module2, ~s("$p1"."id"), ~s("test_fixtures_entity_module3"."b_id"))

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s( WHERE "c_id" IS NOT DISTINCT FROM #{b_id} ORDER BY))
    end

    test "compares two string paths by their sort-key pairs" do
      mapping = path_mapping([Module1, Module2, Module3, Module5])
      term = path_term(Module5, [{[:a, :b, :c], {:<, {:attribute, [:b, :a, :b, :c]}}}])

      key = fn column, outer -> hop(2, Module2, ~s("$p2"."#{column}"), outer) end

      subject_key =
        hop(
          1,
          Module3,
          key.("c_$sort", ~s("$p1"."b_id")),
          ~s("test_fixtures_entity_module5"."a_id")
        )

      subject =
        hop(1, Module3, key.("c", ~s("$p1"."b_id")), ~s("test_fixtures_entity_module5"."a_id"))

      operand_key =
        hop(
          1,
          Module5,
          hop(
            2,
            Module3,
            hop(3, Module2, ~s("$p3"."c_$sort"), ~s("$p2"."b_id")),
            ~s("$p1"."a_id")
          ),
          ~s("test_fixtures_entity_module5"."b_id")
        )

      operand =
        hop(
          1,
          Module5,
          hop(2, Module3, hop(3, Module2, ~s("$p3"."c"), ~s("$p2"."b_id")), ~s("$p1"."a_id")),
          ~s("test_fixtures_entity_module5"."b_id")
        )

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE (#{subject_key}, #{subject}) < (#{operand_key}, #{operand}) ORDER BY|
             )
    end

    test "compares a string path with a bound by its sort-key pair" do
      mapping = path_mapping([Module1, Module2, Module3])
      term = path_term(Module3, [{[:b, :c], {:>=, "M"}}])

      key = hop(1, Module2, ~s("$p1"."c_$sort"), ~s("test_fixtures_entity_module3"."b_id"))
      value = hop(1, Module2, ~s("$p1"."c"), ~s("test_fixtures_entity_module3"."b_id"))

      assert %{params: [{:value, "m"}, {:value, "M"}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE (#{key}, #{value}) >= ($1, $2) ORDER BY|)
    end

    test "casts a path's enum operand to the compared attribute's type" do
      mapping = path_mapping([Module4, Module15, Module24, Module25])
      term = path_term(Module25, [{[:e, :priority], {:attribute, [:e, :level]}}])

      priority =
        hop(1, Module24, ~s("$p1"."priority"), ~s("test_fixtures_entity_module25"."e_id"))

      level = hop(1, Module24, ~s("$p1"."level"), ~s("test_fixtures_entity_module25"."e_id"))

      cast = ~s|::text::"hologram_data"."test_fixtures_entity_module24_priority_$enum"|

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE #{priority} IS NOT DISTINCT FROM #{level}#{cast} ORDER BY|
             )
    end

    test "compiles a nil equality on a path to IS NULL" do
      mapping = path_mapping([Module1, Module2, Module3])
      term = path_term(Module3, [{[:b, :c], nil}])

      b_c = hop(1, Module2, ~s("$p1"."c"), ~s("test_fixtures_entity_module3"."b_id"))

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE #{b_c} IS NULL ORDER BY|)
    end

    # The column the path ends at is required, and a missing related row reads as missing anyway.
    test "widens an inequality on a path to a missing value whatever the column declares" do
      mapping = path_mapping([Module1, Module2, Module3])
      term = path_term(Module3, [{[:b, :a], {:!=, true}}])

      b_a = hop(1, Module2, ~s("$p1"."a"), ~s("test_fixtures_entity_module3"."b_id"))

      assert %{params: [{:value, true}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE (#{b_a} != $1 OR #{b_a} IS NULL) ORDER BY|)
    end

    test "widens a negated membership on a path to a missing value" do
      mapping = path_mapping([Module1, Module2, Module3])
      term = path_term(Module3, [{[:b, :c], {:not_in, ["x"]}}])

      b_c = hop(1, Module2, ~s("$p1"."c"), ~s("test_fixtures_entity_module3"."b_id"))

      assert %{params: [{:value, ["x"]}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE (#{b_c} != ALL($1) OR #{b_c} IS NULL) ORDER BY|)
    end

    test "binds a placeholder on a path with the type of the attribute it ends at" do
      mapping = path_mapping([Module1, Module2, Module3])
      base_term = Stage.normalize(Module3)
      term = %{base_term | filter: [{[:b, :c], :==, {:placeholder, :name}}]}

      assert %{params: [{:placeholder, :name, :string}]} = compile(term, mapping)
    end

    test "applies the hop type's read policy to the row a hop reads under a policied read" do
      mapping = path_mapping([PathSource1, PathTarget1])
      term = path_term(PathSource1, [{[:target, :name], "x"}])
      rules = Policy.build(PathSource1)[:read]

      target_name =
        ~s|(SELECT "$p1"."name" FROM #{table(PathTarget1)} AS "$p1" | <>
          ~s|WHERE "$p1"."id" = "#{Mapper.table_name(PathSource1)}"."target_id" AND "public" = $1)|

      assert %{params: [{:value, true}, {:value, "x"}], sql: sql} =
               compile(term, mapping, %{rules: rules})

      assert String.contains?(sql, ~s| WHERE #{target_name} = $2 ORDER BY|)
    end

    test "reads every row a hop reaches when compiled without a policy" do
      mapping = path_mapping([PathSource1, PathTarget1])
      term = path_term(PathSource1, [{[:target, :name], "x"}])

      assert %{params: [{:value, "x"}], sql: sql} = compile(term, mapping)
      refute String.contains?(sql, ~s("public"))
    end

    # Nobody is the actor, so the hop's actor-naming rule admits no row and the hop reads nothing.
    test "folds an actor-naming hop policy away for an anonymous statement" do
      mapping = path_mapping([Module14, PathSource2, PathTarget2])
      term = path_term(PathSource2, [{[:target, :name], "x"}])
      rules = Policy.build(PathSource2)[:read]

      assert %{params: [{:value, "x"}], sql: sql} =
               compile(term, mapping, %{anonymous?: true, rules: rules})

      assert String.contains?(
               sql,
               ~s|WHERE "$p1"."id" = "#{Mapper.table_name(PathSource2)}"."target_id" AND FALSE) = $1|
             )
    end

    # A policy decides by the rows as stored, so the hop of a rule's own condition applies no read
    # policy even inside a policied statement.
    test "reads a path inside a policy rule raw" do
      mapping = path_mapping([PathSource1, PathTarget1])
      term = Stage.normalize(PathSource1)
      rules = [%{predicates: [{[:target, :name], :==, "x"}], to: nil, via: nil}]

      target_name =
        ~s|(SELECT "$p1"."name" FROM #{table(PathTarget1)} AS "$p1" | <>
          ~s|WHERE "$p1"."id" = "#{Mapper.table_name(PathSource1)}"."target_id")|

      assert %{params: [{:value, "x"}], sql: sql} = compile(term, mapping, %{rules: rules})
      assert String.contains?(sql, ~s| WHERE #{target_name} = $1 ORDER BY|)
    end

    test "correlates a path inside a delegated policy on the delegation's alias" do
      mapping = path_mapping([PathMiddle3, PathSource3, PathTarget1])
      term = Stage.normalize(PathSource3)
      rules = Policy.build(PathSource3)[:read]

      target_public =
        ~s|(SELECT "$p1"."public" FROM #{table(PathTarget1)} AS "$p1" | <>
          ~s|WHERE "$p1"."id" = "$d1"."target_id")|

      assert %{params: [{:value, true}], sql: sql} = compile(term, mapping, %{rules: rules})

      assert String.contains?(
               sql,
               ~s|WHERE "$d1"."id" = "#{Mapper.table_name(PathSource3)}"."middle_id" AND #{target_public} = $1)|
             )
    end

    # The hop's read policy is evaluated on the hop's row, so a path inside it starts from the hop's
    # alias and takes the next number.
    test "numbers a path inside a hop's read policy past the hop" do
      mapping = path_mapping([PathMiddle3, PathTarget1, PathSource4])

      term = path_term(PathSource4, [{[:middle, :id], {:!=, nil}}])
      rules = Policy.build(PathSource4)[:read]

      middle_id =
        ~s|(SELECT "$p1"."id" FROM #{table(PathMiddle3)} AS "$p1" | <>
          ~s|WHERE "$p1"."id" = "#{Mapper.table_name(PathSource4)}"."middle_id" | <>
          ~s|AND (SELECT "$p2"."public" FROM #{table(PathTarget1)} AS "$p2" | <>
          ~s|WHERE "$p2"."id" = "$p1"."target_id") = $1)|

      assert %{params: [{:value, true}], sql: sql} = compile(term, mapping, %{rules: rules})
      assert String.contains?(sql, ~s| WHERE #{middle_id} IS NOT NULL ORDER BY|)
    end

    test "correlates a path inside a to-many include's filter on the include's row" do
      mapping = path_mapping([Module1, Module2, Module3, Module6])

      term =
        Module6
        |> Stage.include(:a, &Stage.filter(&1, [{[:b, :a], true}]))
        |> Stage.normalize()

      b_a = hop(1, Module2, ~s("$p1"."a"), ~s("$t1"."b_id"))

      assert %{params: [{:value, true}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| AND #{b_a} = $1|)
    end
  end
end
