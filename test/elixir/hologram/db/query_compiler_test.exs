defmodule Hologram.DB.QueryCompilerTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.DB

  import Hologram.DB.QueryCompiler

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Mapper
  alias Hologram.MisuseError
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
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module27
  alias Hologram.Test.Fixtures.Entity.Module28
  alias Hologram.Test.Fixtures.Entity.Module29
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module32
  alias Hologram.Test.Fixtures.Entity.Module33
  alias Hologram.Test.Fixtures.Entity.Module34
  alias Hologram.Test.Fixtures.Entity.Module37
  alias Hologram.Test.Fixtures.Entity.Module38
  alias Hologram.Test.Fixtures.Entity.Module39
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Entity.Module40
  alias Hologram.Test.Fixtures.Entity.Module41
  alias Hologram.Test.Fixtures.Entity.Module5
  alias Hologram.Test.Fixtures.Entity.Module6
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module13, as: PolicyModule13
  alias Hologram.Test.Fixtures.Policy.Module17, as: PolicyModule17
  alias Hologram.Test.Fixtures.Policy.Module18, as: PolicyModule18
  alias Hologram.Test.Fixtures.Policy.Module19, as: PolicyModule19
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2
  alias Hologram.Test.Fixtures.Policy.Module26, as: PolicyModule26
  alias Hologram.Test.Fixtures.Policy.Module27, as: PolicyModule27
  alias Hologram.Test.Fixtures.Policy.Module28, as: PolicyModule28
  alias Hologram.Test.Fixtures.Policy.Module29, as: PolicyModule29
  alias Hologram.Test.Fixtures.Policy.Module3, as: PolicyModule3
  alias Hologram.Test.Fixtures.Policy.Module5, as: PolicyModule5
  alias Hologram.Test.Fixtures.Policy.Module6, as: PolicyModule6
  alias Hologram.Test.Fixtures.Policy.Module8, as: PolicyModule8
  alias Hologram.Test.Fixtures.Policy.Module9, as: PolicyModule9
  alias Hologram.Test.Fixtures.Policy.Readers.Module1, as: ReadersModule1
  alias Hologram.Test.Fixtures.Policy.Readers.Module10, as: ReadersModule10
  alias Hologram.Test.Fixtures.Policy.Readers.Module12, as: ReadersModule12
  alias Hologram.Test.Fixtures.Policy.Readers.Module13, as: ReadersModule13
  alias Hologram.Test.Fixtures.Policy.Readers.Module15, as: ReadersModule15
  alias Hologram.Test.Fixtures.Policy.Readers.Module16, as: ReadersModule16
  alias Hologram.Test.Fixtures.Policy.Readers.Module17, as: ReadersModule17
  alias Hologram.Test.Fixtures.Policy.Readers.Module18, as: ReadersModule18
  alias Hologram.Test.Fixtures.Policy.Readers.Module2, as: ReadersModule2
  alias Hologram.Test.Fixtures.Policy.Readers.Module3, as: ReadersModule3
  alias Hologram.Test.Fixtures.Policy.Readers.Module4, as: ReadersModule4
  alias Hologram.Test.Fixtures.Policy.Readers.Module5, as: ReadersModule5
  alias Hologram.Test.Fixtures.Policy.Readers.Module8, as: ReadersModule8
  alias Hologram.Test.Fixtures.Policy.Readers.Module9, as: ReadersModule9
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
    test "compiles equality predicates into bound placeholders" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(a: true, b: 123)
        |> Stage.normalize()

      assert compile(term, mapping) == %{
               params: [{:value, true}, {:value, 123}],
               sql:
                 ~s(SELECT "id", "a", "b", "c", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions" ) <>
                   ~s(FROM "hologram_data"."test_fixtures_entity_module2" ) <>
                   ~s(WHERE "a" = $1 AND "b" = $2 ORDER BY "id" ASC)
             }
    end

    test "applies nested clauses to a to-many include" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term =
        Module3
        |> narrowed_include(:a, fn related_query ->
          related_query
          |> filter(a: true)
          |> sort(c)
          |> take(5)
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
        |> narrowed_include(:a, fn related_query -> sort(related_query, c) end)
        |> Stage.normalize()

      assert %{sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|ORDER BY "$i1"."c_$sort" ASC, "$i1"."c" ASC, "$i1"."id" ASC), '[]'::jsonb|
             )
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
                 ~s(SELECT "id", "b_id", "c_id", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions" ) <>
                   ~s(FROM "hologram_data"."test_fixtures_entity_module3" ) <>
                   ~s(WHERE "c_id" = $1 ORDER BY "id" ASC)
             }
    end

    test "composes a policy rule after the authored filter" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term =
        Module2
        |> filter(a: true)
        |> Stage.normalize()

      rules = [%{predicates: [{:c, :==, "text_1"}], to: nil, via: nil}]

      assert compile(term, mapping, %{rules: rules}) == %{
               params: [{:value, true}, {:value, "text_1"}, {:value, "text_1"}],
               sql:
                 ~s(SELECT "id", "a", "b", "c", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions" ) <>
                   ~s(FROM "hologram_data"."test_fixtures_entity_module2" ) <>
                   ~s|WHERE "a" = $1 AND ("c_$sort" = $2 AND "c" = $3) ORDER BY "id" ASC|
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

      assert String.contains?(
               sql,
               ~s|WHERE (("a" = $1) OR ("b" >= $2 AND ("c_$sort" = $3 AND "c" = $4)))|
             )
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

      assert params == [{:value, true}, {:value, 3}, {:value, "x"}, {:value, "x"}]

      assert String.contains?(
               sql,
               ~s|WHERE (((("a" = $1) OR ("b" >= $2))) OR (("c_$sort" = $3 AND "c" = $4)))|
             )
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

    test "allocates the actor slot after the authored slots" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term =
        Module3
        |> filter(c_id: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")
        |> Stage.normalize()

      rules = [%{predicates: [{:b_id, :==, {:actor}}], to: nil, via: nil}]

      assert %{params: [{:value, _target_id}, :actor], sql: sql} =
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
                   ~s|"created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions" | <>
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
                 ~s|SELECT "id", "public", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions" | <>
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
                   ~s|"created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions" | <>
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
                 ~s|SELECT "id", "parent_id", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions" | <>
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
                 ~s|SELECT "id", "archived", "parent_id", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions" | <>
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
                 ~s|SELECT "id", "archived", "parent_id", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions" | <>
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
                 ~s|SELECT "id", "parent_id", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions" | <>
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
                 ~s|SELECT "id", "archived", "parent_id", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions", | <>
                   ~s|(SELECT jsonb_build_object('id', "$i1"."id", 'archived', "$i1"."archived", | <>
                   ~s|'parent_id', "$i1"."parent_id", 'created_at', "$i1"."created_at", | <>
                   ~s|'server_created_at', "$i1"."server_created_at", | <>
                   ~s|'server_updated_at', "$i1"."server_updated_at", | <>
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

      assert %{params: [], sql: sql} = compile(term, mapping, %{rules: rules})

      assert String.contains?(sql, ~s| WHERE FALSE ORDER BY|)
    end

    test "numbers the slots of the rules after a dropped one from where it started" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])
      term = Stage.normalize(PolicyModule1)

      rules = [
        %{predicates: [{:priority, :>=, 3}], to: nil, via: nil},
        %{predicates: [{:author_id, :==, {:actor}}], to: nil, via: {:delete, [:parent]}},
        %{predicates: [{:public, :==, true}], to: [{:own, [:viewer]}], via: nil}
      ]

      assert %{params: [{:value, 3}, {:value, true}, :actor | _grant_slots], sql: sql} =
               compile(term, mapping, %{rules: rules})

      assert String.contains?(sql, ~s|WHERE (("priority" >= $1) OR ("public" = $2 AND |)
      assert String.contains?(sql, ~s|"$rg"."user_id" = $3 |)
    end

    test "drops a rule whose delegation never holds from the group, with its slots" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])
      term = Stage.normalize(PolicyModule1)

      rules = [
        %{predicates: [{:priority, :==, 1}], to: nil, via: {:delete, [:parent]}},
        %{predicates: [{:public, :==, true}], to: nil, via: nil}
      ]

      assert %{params: [{:value, true}], sql: sql} = compile(term, mapping, %{rules: rules})

      assert String.contains?(sql, ~s| WHERE "public" = $1 ORDER BY|)
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
                ["Hologram.Test.Fixtures.Role.Module1", "Hologram.Test.Fixtures.Role.Module2"]},
               {:value, "Hologram.Test.Fixtures.Policy.Module40"},
               {:value, ["owner"]},
               {:value, "Hologram.Test.Fixtures.Policy.Module40"}
             ]

      assert String.contains?(sql, ~s|WHERE (("user_id" = $1)|)

      assert String.contains?(
               sql,
               ~s|("entity_type" = $2 AND EXISTS (SELECT 1 FROM | <>
                 ~s|"hologram_data"."hologram_role_grant" AS "$rg" WHERE "$rg"."user_id" = $1 | <>
                 ~s|AND "$rg"."role" = ANY($3::"hologram_data"."hologram_role_grant_role_$enum"[]) | <>
                 ~s|AND "$rg"."entity_type" = | <>
                 ~s|$4::"hologram_data"."hologram_role_grant_entity_type_$enum" | <>
                 ~s|AND "hologram_role_grant"."entity_id" IS NOT NULL | <>
                 ~s|AND ("$rg"."entity_id" = "hologram_role_grant"."entity_id" | <>
                 ~s|OR "$rg"."entity_id" IS NULL)))|
             )
    end

    test "compiles a disjunction as an OR group of its alternatives" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(a == true or (b >= 3 and c == "x"))
        |> Stage.normalize()

      assert compile(term, mapping) == %{
               params: [{:value, true}, {:value, 3}, {:value, "x"}, {:value, "x"}],
               sql:
                 ~s(SELECT "id", "a", "b", "c", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions" ) <>
                   ~s(FROM "hologram_data"."test_fixtures_entity_module2" ) <>
                   ~s|WHERE (("a" = $1) OR ("b" >= $2 AND ("c_$sort" = $3 AND "c" = $4))) | <>
                   ~s|ORDER BY "id" ASC|
             }
    end

    test "compiles a disjunction before the conjuncts beside it" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(a: true)
        |> filter(b == 1 or c == "x")
        |> Stage.normalize()

      assert %{params: [{:value, 1}, {:value, "x"}, {:value, "x"}, {:value, true}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|WHERE (("b" = $1) OR (("c_$sort" = $2 AND "c" = $3))) AND "a" = $4 ORDER BY|
             )
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

      assert params == [
               {:value, "x"},
               {:value, "x"},
               {:value, "y"},
               {:value, "y"},
               {:value, 3},
               {:value, true}
             ]

      assert String.contains?(
               sql,
               ~s|WHERE ((((("c_$sort" = $1 AND "c" = $2)) OR (("c_$sort" = $3 AND "c" = $4))) | <>
                 ~s|AND "b" >= $5) OR ("a" = $6)) ORDER BY|
             )
    end

    test "keeps a disjunction inside a to-many include's filter" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term =
        Module3
        |> narrowed_include(:a, &filter(&1, a == true or c == "x"))
        |> Stage.normalize()

      assert %{params: [{:value, true}, {:value, "x"}, {:value, "x"}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| AND (("a" = $1) OR (("c_$sort" = $2 AND "c" = $3))) ORDER BY "id" ASC|
             )
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

    test "compiles take and skip as literal LIMIT and OFFSET" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> take(50)
        |> skip(20)
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

      assert %{params: [{:value, ["x", "y"]}, {:value, ["x", "y"]}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(sql, ~s| WHERE ("c_$sort" = ANY($1) AND "c" = ANY($2))|)
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

    test "compiles nil-holding string membership with its keys inside the IS NULL branch" do
      mapping = Mapper.derive!([Module10], [])
      term = %{Stage.normalize(Module10) | filter: [{:username, :in, [nil, "Ann", "bob"]}]}

      assert %{params: [{:value, ["ann", "bob"]}, {:value, ["Ann", "bob"]}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE (("username_$sort" = ANY($1) AND "username" = ANY($2)) | <>
                 ~s|OR "username" IS NULL)|
             )
    end

    test "raises on a literal that isn't a string compared with a string attribute" do
      mapping = Mapper.derive!([Module2], [])
      term = %{Stage.normalize(Module2) | filter: [{:c, :==, 5}]}

      assert_raise MisuseError, "a string attribute compares with a string, got: 5", fn ->
        compile(term, mapping)
      end
    end

    test "compiles a string equality with the literal's sort key ahead of its value" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> filter(c == "Ann")
        |> Stage.normalize()

      assert %{params: [{:value, "ann"}, {:value, "Ann"}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE ("c_$sort" = $1 AND "c" = $2) ORDER BY|)
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
        |> take(50)
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
          ~s|'created_at', "$i1"."created_at", 'server_created_at', "$i1"."server_created_at", 'server_updated_at', "$i1"."server_updated_at", 'updated_at', "$i1"."updated_at", '$revisions', "$i1"."$revisions"| <>
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
                 ~s|SELECT "id", "b_id", "c_id", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions", | <>
                   ~s|(SELECT jsonb_build_object('id', "$i1"."id", 'created_at', "$i1"."created_at", 'server_created_at', "$i1"."server_created_at", 'server_updated_at', "$i1"."server_updated_at", 'updated_at', "$i1"."updated_at", '$revisions', "$i1"."$revisions") | <>
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
        |> sort(b: :desc, c: :asc)
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

    test "compares a string inside an include through the include's companion" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term =
        Module3
        |> narrowed_include(:a, fn related_query -> filter(related_query, c >= "Zoe") end)
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

    test "binds no slot for an attribute operand beside a literal" do
      mapping = Mapper.derive!([Module10], [])

      term = %{
        Stage.normalize(Module10)
        | filter: [{:count, :<, {:attribute, :priority}}, {:username, :==, "dan"}]
      }

      # The string's sort key binds first, then its value - "dan" is its own key.
      assert %{params: [{:value, "dan"}, {:value, "dan"}], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE "count" < "priority" AND ("username_$sort" = $1 AND "username" = $2) |
             )
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
        |> sort(c: :desc)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)
      assert String.ends_with?(sql, ~s( ORDER BY "c_$sort" DESC, "c" DESC, "id" ASC))
    end

    test "compiles single-result queries with a zero take as zero" do
      mapping = Mapper.derive!([Module2], [])

      term =
        Module2
        |> take(0)
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
          ~s|'created_at', "$i2"."created_at", 'server_created_at', "$i2"."server_created_at", 'server_updated_at', "$i2"."server_updated_at", 'updated_at', "$i2"."updated_at", '$revisions', "$i2"."$revisions"| <>
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

    test "reads an inverse set of a to-one through the related rows' reference column" do
      mapping = Mapper.derive!([Module26, Module27, Module28, Module29], [])

      term =
        Module26
        |> include(messages)
        |> Stage.normalize()

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s|SELECT "id", "name", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions", | <>
                   ~s|(SELECT COALESCE(jsonb_agg(jsonb_build_object(| <>
                   ~s|'id', "$i1"."id", 'body', "$i1"."body", 'position', "$i1"."position", 'channel_id', "$i1"."channel_id", | <>
                   ~s|'created_at', "$i1"."created_at", 'server_created_at', "$i1"."server_created_at", 'server_updated_at', "$i1"."server_updated_at", 'updated_at', "$i1"."updated_at", '$revisions', "$i1"."$revisions") | <>
                   ~s|ORDER BY "$i1"."position" ASC, "$i1"."id" ASC), '[]'::jsonb) | <>
                   ~s|FROM (SELECT "$t1".* FROM "hologram_data"."test_fixtures_entity_module28" AS "$t1" | <>
                   ~s|WHERE "$t1"."channel_id" = "test_fixtures_entity_module26"."id" | <>
                   ~s|ORDER BY "position" ASC, "id" ASC) AS "$i1") AS "messages" | <>
                   ~s|FROM "hologram_data"."test_fixtures_entity_module26" ORDER BY "id" ASC|
             }
    end

    test "reads a single inverse through the related row's reference column" do
      mapping = Mapper.derive!([Module26, Module27, Module28, Module29], [])

      term =
        Module26
        |> include(topic)
        |> Stage.normalize()

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s|SELECT "id", "name", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions", | <>
                   ~s|(SELECT jsonb_build_object(| <>
                   ~s|'id', "$i1"."id", 'code', "$i1"."code", 'summary', "$i1"."summary", 'channel_id', "$i1"."channel_id", | <>
                   ~s|'created_at', "$i1"."created_at", 'server_created_at', "$i1"."server_created_at", 'server_updated_at', "$i1"."server_updated_at", 'updated_at', "$i1"."updated_at", '$revisions', "$i1"."$revisions") | <>
                   ~s|FROM "hologram_data"."test_fixtures_entity_module27" AS "$i1" | <>
                   ~s|WHERE "$i1"."channel_id" = "test_fixtures_entity_module26"."id") AS "topic" | <>
                   ~s|FROM "hologram_data"."test_fixtures_entity_module26" ORDER BY "id" ASC|
             }
    end

    test "reads an inverse set of a to-many through the related type's join table, read backwards" do
      mapping = Mapper.derive!([Module26, Module27, Module28, Module29], [])

      term =
        Module29
        |> include(messages)
        |> Stage.normalize()

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s|SELECT "id", "name", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions", | <>
                   ~s|(SELECT COALESCE(jsonb_agg(jsonb_build_object(| <>
                   ~s|'id', "$i1"."id", 'body', "$i1"."body", 'position', "$i1"."position", 'channel_id', "$i1"."channel_id", | <>
                   ~s|'created_at', "$i1"."created_at", 'server_created_at', "$i1"."server_created_at", 'server_updated_at', "$i1"."server_updated_at", 'updated_at', "$i1"."updated_at", '$revisions', "$i1"."$revisions") | <>
                   ~s|ORDER BY "$i1"."id" ASC), '[]'::jsonb) | <>
                   ~s|FROM (SELECT "$t1".* FROM "hologram_data"."test_fixtures_entity_module28" AS "$t1" | <>
                   ~s|WHERE "$t1"."id" IN (SELECT "$j1"."source_id" | <>
                   ~s|FROM "hologram_data"."test_fixtures_entity_module28_labels_$join" AS "$j1" | <>
                   ~s|WHERE "$j1"."target_id" = "test_fixtures_entity_module29"."id") | <>
                   ~s|ORDER BY "id" ASC) AS "$i1") AS "messages" | <>
                   ~s|FROM "hologram_data"."test_fixtures_entity_module29" ORDER BY "id" ASC|
             }
    end

    test "matches an inverse below the root to the row including it" do
      mapping = Mapper.derive!([Module26, Module27, Module28, Module29], [])

      term =
        Module28
        |> include([channel.messages, channel.topic])
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(sql, ~s|WHERE "$t2"."channel_id" = "$i1"."id"|)
      assert String.contains?(sql, ~s|WHERE "$i3"."channel_id" = "$i1"."id"|)
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

    test "selects the mapped columns in physical order, leaving out the derived companions" do
      mapping = Mapper.derive!([Module2], [])
      term = Stage.normalize(Module2)

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s(SELECT "id", "a", "b", "c", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions" FROM "hologram_data"."test_fixtures_entity_module2" ORDER BY "id" ASC)
             }
    end

    test "selects reference columns for to-one relationships" do
      mapping = Mapper.derive!([Module2, Module3], [])
      term = Stage.normalize(Module3)

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s(SELECT "id", "b_id", "c_id", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions" FROM "hologram_data"."test_fixtures_entity_module3" ORDER BY "id" ASC)
             }
    end

    test "threads include slots after the root's" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      term =
        Module3
        |> filter(id: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")
        |> narrowed_include(:a, &filter(&1, a: true))
        |> Stage.normalize()

      assert %{params: [{:value, _root_id}, {:value, true}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(sql, ~s( WHERE "id" = $1))
      assert String.contains?(sql, ~s( AND "a" = $2))
    end
  end

  describe "compile/2 - acting user expressions" do
    # A statement deciding for many users at once reads each one off a row of its own, so the policy
    # names the column it is read from instead of binding a slot.
    @actor_sql ~s|"$x"."$user"|

    test "compares a name to the expression" do
      mapping = Mapper.derive!([Module14], [])
      term = Stage.normalize(Module14)
      rules = [%{predicates: [{:id, :==, {:actor}}], to: nil, via: nil}]

      assert %{params: [], sql: sql} =
               compile(term, mapping, %{actor_sql: @actor_sql, rules: rules})

      assert String.contains?(sql, ~s| WHERE "id" = "$x"."$user" |)
    end

    test "compares a name to the expression in an inequality, nil kept unequal" do
      mapping = Mapper.derive!([Module14, PolicyModule6], [])
      term = Stage.normalize(PolicyModule6)
      rules = [%{predicates: [{:author_id, :!=, {:actor}}], to: nil, via: nil}]

      assert %{params: [], sql: sql} =
               compile(term, mapping, %{actor_sql: @actor_sql, rules: rules})

      assert String.contains?(
               sql,
               ~s| WHERE ("author_id" != "$x"."$user" OR "author_id" IS NULL) |
             )
    end

    test "reads the expression inside a quantifier's condition" do
      mapping = Mapper.derive!([Module14, ReadersModule1, ReadersModule2, ReadersModule3], [])
      term = Stage.normalize(ReadersModule1)
      policy = %{actor_sql: @actor_sql, rules: Policy.build(ReadersModule1)[:read]}

      assert %{params: [], sql: sql} = compile(term, mapping, policy)

      assert String.contains?(
               sql,
               ~s|WHERE EXISTS (SELECT 1 FROM "hologram_data"."test_fixtures_policy_readers_module2" | <>
                 ~s|AS "$q1" WHERE "$q1"."project_id" = "test_fixtures_policy_readers_module1"."id" | <>
                 ~s|AND "user_id" = "$x"."$user")|
             )
    end

    test "looks grants up for the expression" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])
      term = Stage.normalize(PolicyModule1)
      rules = [%{predicates: [], to: [{:own, [:owner]}], via: nil}]

      assert %{params: params, sql: sql} =
               compile(term, mapping, %{actor_sql: @actor_sql, rules: rules})

      refute :actor in params
      assert String.contains?(sql, ~s|WHERE "$rg"."user_id" = "$x"."$user" AND "$rg"."role"|)
    end

    test "carries the expression into a delegated policy" do
      mapping = Mapper.derive!([Module14, PolicyModule1, PolicyModule2, RoleGrant], [])
      term = Stage.normalize(PolicyModule1)
      rules = [%{predicates: [], to: nil, via: {:read, [:parent]}}]

      assert %{params: params, sql: sql} =
               compile(term, mapping, %{actor_sql: @actor_sql, rules: rules})

      refute :actor in params

      assert String.contains?(
               sql,
               ~s|AS "$d1" WHERE "$d1"."id" = "test_fixtures_policy_module1"."parent_id" | <>
                 ~s|AND EXISTS (SELECT 1 FROM "hologram_data"."hologram_role_grant" AS "$rg" | <>
                 ~s|WHERE "$rg"."user_id" = "$x"."$user" |
             )
    end

    test "carries the expression into the read policy of an included type" do
      mapping =
        Mapper.derive!([Module14, PolicyModule1, PolicyModule2, PolicyModule3, RoleGrant], [])

      term =
        PolicyModule3
        |> include(children)
        |> Stage.normalize()

      policy = %{actor_sql: @actor_sql, rules: Policy.build(PolicyModule3)[:read]}

      assert %{params: params, sql: sql} = compile(term, mapping, policy)

      refute :actor in params
      assert String.contains?(sql, ~s|WHERE "$rg"."user_id" = "$x"."$user" |)
    end

    test "carries the expression into the carried rules of a delegation, disjunctions included" do
      mapping =
        Mapper.derive!([Module14, PolicyModule1, PolicyModule2, PolicyModule5, RoleGrant], [])

      term = Stage.normalize(PolicyModule5)

      carried_rule = %{
        predicates: [{:or, [[{:author_id, :==, {:actor}}], [{:public, :==, true}]]}],
        to: nil,
        via: nil
      }

      rules = [%{predicates: [], to: nil, via: {:read, [:parent], [carried_rule]}}]

      assert %{params: [{:value, true}], sql: sql} =
               compile(term, mapping, %{actor_sql: @actor_sql, rules: rules})

      assert String.contains?(
               sql,
               ~s|AS "$d1" WHERE "$d1"."id" = "test_fixtures_policy_module5"."parent_id" | <>
                 ~s|AND (("author_id" = "$x"."$user") OR ("public" = $1)))|
             )
    end

    test "binds the acting user's slot without an expression" do
      mapping = Mapper.derive!([Module14], [])
      term = Stage.normalize(Module14)
      rules = [%{predicates: [{:id, :==, {:actor}}], to: nil, via: nil}]

      assert %{params: [:actor], sql: sql} = compile(term, mapping, %{rules: rules})

      assert String.contains?(sql, ~s| WHERE "id" = $1 |)
    end
  end

  describe "compile/2 - delegations carrying their rules" do
    test "asks the related row the carried rules only" do
      mapping =
        Mapper.derive!([Module14, PolicyModule1, PolicyModule2, PolicyModule5, RoleGrant], [])

      term = Stage.normalize(PolicyModule5)
      public_rule = %{predicates: [{:public, :==, true}], to: nil, via: nil}
      rules = [%{predicates: [], to: nil, via: {:read, [:parent], [public_rule]}}]

      assert compile(term, mapping, %{rules: rules}) == %{
               params: [{:value, true}],
               sql:
                 ~s|SELECT "id", "parent_id", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions" | <>
                   ~s|FROM "hologram_data"."test_fixtures_policy_module5" | <>
                   ~s|WHERE EXISTS (SELECT 1 FROM "hologram_data"."test_fixtures_policy_module1" | <>
                   ~s|AS "$d1" WHERE "$d1"."id" = "test_fixtures_policy_module5"."parent_id" | <>
                   ~s|AND "public" = $1) ORDER BY "id" ASC|
             }
    end

    test "never holds when it carries no rules" do
      mapping =
        Mapper.derive!([Module14, PolicyModule1, PolicyModule2, PolicyModule5, RoleGrant], [])

      term = Stage.normalize(PolicyModule5)
      rules = [%{predicates: [], to: nil, via: {:read, [:parent], []}}]

      assert %{params: [], sql: sql} = compile(term, mapping, %{rules: rules})

      assert String.contains?(sql, ~s| WHERE FALSE ORDER BY|)
    end
  end

  describe "compile/2 - derived counts and sets" do
    setup do
      put_derived_definitions([Module32, Module33, Module34, Module37, Module38, Module40])

      mapping =
        Mapper.derive!(
          [
            Module1,
            Module2,
            Module32,
            Module33,
            Module34,
            Module37,
            Module38,
            Module40,
            Module41
          ],
          []
        )

      [mapping: mapping]
    end

    test "counts the rows a source leads to in a correlated subquery", %{mapping: mapping} do
      term =
        Module32
        |> filter(message_count > 1)
        |> sort(message_count: :desc)
        |> Stage.normalize()

      message_count =
        ~s|(SELECT count(*) FROM #{table(Module33)} AS "$s1" | <>
          ~s|WHERE "$s1"."channel_id" = "test_fixtures_entity_module32"."id")|

      assert %{params: [{:value, 1}], sql: sql} = compile(term, mapping)

      assert String.ends_with?(
               sql,
               ~s| WHERE #{message_count} > $1 ORDER BY #{message_count} DESC, "id" ASC|
             )
    end

    test "reads the owner row as the row above a count's rows", %{mapping: mapping} do
      term =
        Module33
        |> filter(later_count == 0)
        |> Stage.normalize()

      channel =
        ~s|EXISTS (SELECT 1 FROM #{table(Module32)} AS "$s1_1" | <>
          ~s|WHERE "$s1_1"."id" = "test_fixtures_entity_module33"."channel_id" | <>
          ~s|AND "$s1"."channel_id" = "$s1_1"."id")|

      later_count =
        ~s|(SELECT count(*) FROM #{table(Module33)} AS "$s1" WHERE #{channel} | <>
          ~s|AND "position" > "test_fixtures_entity_module33"."position")|

      assert %{params: [{:value, 0}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE #{later_count} = $1 ORDER BY|)
    end

    test "flattens a source through a set into the rows it reaches", %{mapping: mapping} do
      term =
        Module40
        |> filter(mentor_message_count == 2)
        |> Stage.normalize()

      mentors =
        ~s|EXISTS (SELECT 1 FROM #{table(Module34)} AS "$s1_1" WHERE "$s1_1"."id" IN | <>
          ~s|(SELECT "$sj1"."target_id" FROM "hologram_data"."test_fixtures_entity_module40_mentors_$join" AS "$sj1" | <>
          ~s|WHERE "$sj1"."source_id" = "test_fixtures_entity_module40"."id") | <>
          ~s|AND "$s1_2"."id" = "$s1_1"."channel_id")|

      channels =
        ~s|EXISTS (SELECT 1 FROM #{table(Module32)} AS "$s1_2" WHERE #{mentors} | <>
          ~s|AND "$s1"."channel_id" = "$s1_2"."id")|

      assert %{params: [{:value, 2}], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE (SELECT count(*) FROM #{table(Module33)} AS "$s1" WHERE #{channels}) = $1 ORDER BY|
             )
    end

    test "caps a count by its bounds", %{mapping: mapping} do
      term =
        Module40
        |> filter(capped_note_count == 2)
        |> Stage.normalize()

      assert %{params: [{:value, 2}], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE (SELECT count(*) FROM (SELECT 1 FROM #{table(Module41)} AS "$s1" | <>
                 ~s|WHERE "$s1"."team_id" = "test_fixtures_entity_module40"."id" LIMIT 2) AS "$sc1") = $1 ORDER BY|
             )
    end

    test "applies the related type's read policy inside a count", %{mapping: mapping} do
      term =
        Module40
        |> filter(note_count > 0)
        |> Stage.normalize()

      policy = %{rules: [%{predicates: [], to: nil, via: nil}]}

      assert %{params: [{:value, true}, {:value, 0}], sql: sql} = compile(term, mapping, policy)

      assert String.contains?(
               sql,
               ~s| WHERE (SELECT count(*) FROM #{table(Module41)} AS "$s1" | <>
                 ~s|WHERE "$s1"."team_id" = "test_fixtures_entity_module40"."id" AND "public" = $1) > $2 ORDER BY|
             )
    end

    test "widens a count a float field reads", %{mapping: mapping} do
      term =
        Module40
        |> filter(note_weight > 1.5)
        |> Stage.normalize()

      assert %{params: [{:value, 1.5}], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE (SELECT count(*) FROM #{table(Module41)} AS "$s1" | <>
                 ~s|WHERE "$s1"."team_id" = "test_fixtures_entity_module40"."id")::float8 > $1 ORDER BY|
             )
    end

    test "matches a quantifier's rows to a derived set's bounded, ordered rows", %{
      mapping: mapping
    } do
      term =
        Module32
        |> filter(any(message <- recent_messages, message.position == 1))
        |> Stage.normalize()

      recent_messages =
        ~s|SELECT "$s2"."id" FROM #{table(Module33)} AS "$s2" | <>
          ~s|WHERE "$s2"."channel_id" = "test_fixtures_entity_module32"."id" | <>
          ~s|ORDER BY "position" DESC, "id" ASC LIMIT 2|

      assert %{params: [{:value, 1}], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE EXISTS (SELECT 1 FROM #{table(Module33)} AS "$q1" | <>
                 ~s|WHERE "$q1"."id" IN (#{recent_messages}) AND "position" = $1) ORDER BY|
             )
    end

    test "reads a count at a path's end on the row the path reaches", %{mapping: mapping} do
      term =
        Module34
        |> filter(channel_load > 0)
        |> Stage.normalize()

      message_count =
        ~s|(SELECT count(*) FROM #{table(Module33)} AS "$s1" WHERE "$s1"."channel_id" = "$p1"."id")|

      channel_load =
        hop(1, Module32, message_count, ~s("test_fixtures_entity_module34"."channel_id"))

      assert %{params: [{:value, 0}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| WHERE #{channel_load} > $1 ORDER BY|)
    end

    test "counts the rows of a quantifier's related row", %{mapping: mapping} do
      term =
        Module37
        |> filter(any(message <- messages, message.sibling_count > 1))
        |> Stage.normalize()

      sibling_count =
        ~s|(SELECT count(*) FROM #{table(Module38)} AS "$s1" | <>
          ~s|WHERE EXISTS (SELECT 1 FROM #{table(Module37)} AS "$s1_1" | <>
          ~s|WHERE "$s1_1"."id" = "$q1"."channel_id" AND "$s1"."channel_id" = "$s1_1"."id"))|

      assert %{params: [{:value, 1}], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| AND #{sibling_count} > $1) ORDER BY|
             )
    end

    test "reaches a derived set through a quantifier source's to-ones", %{mapping: mapping} do
      term =
        Module33
        |> filter(any(message <- channel.recent_messages, message.position == 3))
        |> Stage.normalize()

      recent_messages =
        ~s|SELECT "$s2"."id" FROM #{table(Module33)} AS "$s2" | <>
          ~s|WHERE "$s2"."channel_id" = "$s1_1"."id" ORDER BY "position" DESC, "id" ASC LIMIT 2|

      channel =
        ~s|EXISTS (SELECT 1 FROM #{table(Module32)} AS "$s1_1" | <>
          ~s|WHERE "$s1_1"."id" = "test_fixtures_entity_module33"."channel_id" | <>
          ~s|AND "$q1"."id" IN (#{recent_messages}))|

      assert %{params: [{:value, 3}], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE EXISTS (SELECT 1 FROM #{table(Module33)} AS "$q1" WHERE #{channel} | <>
                 ~s|AND "position" = $1) ORDER BY|
             )
    end

    test "reads the rows of the branch an if chooses, nested a level deeper", %{mapping: mapping} do
      term =
        Module37
        |> filter(picked_count > 0)
        |> Stage.normalize()

      first_message =
        ~s|SELECT "$s2"."id" FROM #{table(Module38)} AS "$s2" | <>
          ~s|WHERE "$s2"."channel_id" = "test_fixtures_entity_module37"."id" ORDER BY "id" ASC LIMIT 1|

      messages =
        ~s|EXISTS (SELECT 1 FROM #{table(Module38)} AS "$s2_1" | <>
          ~s|WHERE "$s2_1"."channel_id" = "test_fixtures_entity_module37"."id" | <>
          ~s|AND "$s2_2"."id" = "$s2_1"."channel_id")|

      colleagues =
        ~s|SELECT "$s2"."id" FROM #{table(Module38)} AS "$s2" | <>
          ~s|WHERE EXISTS (SELECT 1 FROM #{table(Module37)} AS "$s2_2" WHERE #{messages} | <>
          ~s|AND "$s2"."channel_id" = "$s2_2"."id")|

      picked =
        ~s|CASE WHEN ("test_fixtures_entity_module37"."name_$sort" = $1 | <>
          ~s|AND "test_fixtures_entity_module37"."name" = $2) | <>
          ~s|THEN "$s1"."id" IN (#{first_message}) ELSE "$s1"."id" IN (#{colleagues}) END|

      assert %{params: [{:value, "general"}, {:value, "general"}, {:value, 0}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE (SELECT count(*) FROM #{table(Module38)} AS "$s1" WHERE #{picked}) > $3 ORDER BY|
             )
    end

    test "holds no rows for a nil definition", %{mapping: mapping} do
      term =
        Module37
        |> filter(any(nothing))
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE EXISTS (SELECT 1 FROM #{table(Module38)} AS "$q1" WHERE FALSE) ORDER BY|
             )
    end
  end

  describe "compile/2 - derived fields" do
    setup do
      put_derived_definitions([Module34, Module39])

      [mapping: Mapper.derive!([Module32, Module33, Module34, Module39], [])]
    end

    test "binds a literal a definition holds, cast to the declared type", %{mapping: mapping} do
      term =
        Module34
        |> filter(top_score == 10)
        |> Stage.normalize()

      assert compile(term, mapping) == %{
               params: [{:value, 10}, {:value, 10}],
               sql:
                 ~s(SELECT "id", "nickname", "score", "channel_id", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions" ) <>
                   ~s(FROM "hologram_data"."test_fixtures_entity_module34" ) <>
                   ~s(WHERE $1::int8 = $2 ORDER BY "id" ASC)
             }
    end

    test "widens an integer attribute a float field reads", %{mapping: mapping} do
      term =
        Module39
        |> filter(ratio > 1.5)
        |> Stage.normalize()

      assert %{params: [{:value, 1.5}], sql: sql} = compile(term, mapping)

      assert String.contains?(sql, ~s( WHERE "score"::float8 > $1 ORDER BY))
    end

    test "reads an enum attribute an enum field reads as its label", %{mapping: mapping} do
      term =
        Module39
        |> filter(kind_label == :staff)
        |> Stage.normalize()

      assert %{params: [{:value, "staff"}], sql: sql} = compile(term, mapping)

      assert String.contains?(sql, ~s( WHERE "kind"::text = $1 ORDER BY))
    end

    test "concatenates the operands of <> with ||", %{mapping: mapping} do
      term =
        Module34
        |> filter(display_name == "ann (general)")
        |> Stage.normalize()

      channel_name =
        hop(1, Module32, ~s("$p1"."name"), ~s("test_fixtures_entity_module34"."channel_id"))

      assert %{
               params: [{:value, " ("}, {:value, ")"}, {:value, "ann (general)"}],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE ("nickname" \|\| $1::text \|\| #{channel_name} \|\| $2::text) = $3 ORDER BY|
             )
    end

    test "widens an inequality on a derived value to a missing one", %{mapping: mapping} do
      term =
        Module34
        |> filter(display_name != "ann (general)")
        |> Stage.normalize()

      channel_name =
        hop(1, Module32, ~s("$p1"."name"), ~s("test_fixtures_entity_module34"."channel_id"))

      display_name = ~s|("nickname" \|\| $1::text \|\| #{channel_name} \|\| $2::text)|

      assert %{params: [{:value, " ("}, {:value, ")"}, {:value, "ann (general)"}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE (#{display_name} != $3 OR #{display_name} IS NULL) ORDER BY|
             )
    end

    test "compiles if to CASE WHEN, a missing else branch to NULL", %{mapping: mapping} do
      term =
        Module34
        |> filter(badge == "top")
        |> Stage.normalize()

      assert %{params: [{:value, 3}, {:value, "top"}, {:value, "top"}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(
               sql,
               ~s( WHERE CASE WHEN "score" >= $1 THEN $2::text ELSE NULL::text END = $3 ORDER BY)
             )
    end

    test "compiles a condition field to a value false where the condition is not true", %{
      mapping: mapping
    } do
      term =
        Module34
        |> filter(active == true)
        |> Stage.normalize()

      assert %{params: [{:value, 0}, {:value, 3}, {:value, true}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE COALESCE(("score" > $1 AND "score" < $2), false) = $3 ORDER BY|
             )
    end

    test "computes a derived field another definition reads", %{mapping: mapping} do
      term =
        Module39
        |> filter(gold == true)
        |> Stage.normalize()

      tier =
        ~s(CASE WHEN "score" > $1 THEN $2::text ELSE ) <>
          ~s(CASE WHEN "score" > $3 THEN $4::text ELSE $5::text END END)

      assert %{
               params: [
                 {:value, 10},
                 {:value, "gold"},
                 {:value, 5},
                 {:value, "silver"},
                 {:value, "bronze"},
                 {:value, "gold"},
                 {:value, true}
               ],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(sql, ~s| WHERE COALESCE((#{tier} = $6), false) = $7 ORDER BY|)
    end

    test "computes a derived field a path ends at on the row the path reaches", %{
      mapping: mapping
    } do
      term =
        Module39
        |> filter(member.display_name == "ann (general)")
        |> Stage.normalize()

      channel_name = hop(2, Module32, ~s("$p2"."name"), ~s("$p1"."channel_id"))

      display_name =
        hop(
          1,
          Module34,
          ~s|("$p1"."nickname" \|\| $1::text \|\| #{channel_name} \|\| $2::text)|,
          ~s("test_fixtures_entity_module39"."member_id")
        )

      assert %{
               params: [{:value, " ("}, {:value, ")"}, {:value, "ann (general)"}],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(sql, ~s( WHERE #{display_name} = $3 ORDER BY))
    end

    test "compares a derived enum by its label's declared position", %{mapping: mapping} do
      term =
        Module39
        |> filter(tier < :bronze)
        |> Stage.normalize()

      tier =
        ~s(CASE WHEN "score" > $1 THEN $2::text ELSE ) <>
          ~s(CASE WHEN "score" > $3 THEN $4::text ELSE $5::text END END)

      labels = "ARRAY['gold', 'silver', 'bronze']"

      assert %{
               params: [
                 {:value, 10},
                 {:value, "gold"},
                 {:value, 5},
                 {:value, "silver"},
                 {:value, "bronze"},
                 {:value, "bronze"}
               ],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE array_position(#{labels}, #{tier}) < array_position(#{labels}, $6) ORDER BY|
             )
    end

    test "sorts by a derived enum in its declared order", %{mapping: mapping} do
      term =
        Module39
        |> sort(tier: :desc)
        |> Stage.normalize()

      tier =
        ~s(CASE WHEN "score" > $1 THEN $2::text ELSE ) <>
          ~s(CASE WHEN "score" > $3 THEN $4::text ELSE $5::text END END)

      assert %{
               params: [
                 {:value, 10},
                 {:value, "gold"},
                 {:value, 5},
                 {:value, "silver"},
                 {:value, "bronze"}
               ],
               sql: sql
             } = compile(term, mapping)

      assert String.ends_with?(
               sql,
               ~s| ORDER BY array_position(ARRAY['gold', 'silver', 'bronze'], #{tier}) DESC, "id" ASC|
             )
    end

    test "compares a derived value with an attribute of the row", %{mapping: mapping} do
      where_sql = fn query ->
        %{params: [], sql: sql} =
          query
          |> Stage.normalize()
          |> compile(mapping)

        [_select_sql, condition_sql] = String.split(sql, " WHERE ")

        String.replace_suffix(condition_sql, ~s( ORDER BY "id" ASC), "")
      end

      labels = "ARRAY['guest', 'staff']"
      kind_type = ~s("hologram_data"."test_fixtures_entity_module39_kind_$enum")

      widened_sql =
        Module39
        |> filter(ratio > score)
        |> where_sql.()

      label_sql =
        Module39
        |> filter(kind_label <= kind)
        |> where_sql.()

      enum_sql =
        Module39
        |> filter(kind == kind_label)
        |> where_sql.()

      assert widened_sql == ~s("score"::float8 > "score")

      assert label_sql ==
               ~s|array_position(#{labels}, "kind"::text) <= array_position(#{labels}, "kind"::text)|

      assert enum_sql == ~s("kind" IS NOT DISTINCT FROM "kind"::text::#{kind_type})
    end

    test "computes a derived field of the related row inside a quantifier's condition", %{
      mapping: mapping
    } do
      term =
        Module39
        |> filter(any(mentor <- mentors, mentor.active == true))
        |> Stage.normalize()

      assert %{params: [{:value, 0}, {:value, 3}, {:value, true}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| AND COALESCE(("score" > $1 AND "score" < $2), false) = $3) ORDER BY|
             )
    end

    test "computes a derived field of a row above inside a quantifier's condition", %{
      mapping: mapping
    } do
      term =
        Module39
        |> filter(any(mentor <- mentors, mentor.score > ratio and tier == :gold))
        |> Stage.normalize()

      row_score = ~s("test_fixtures_entity_module39"."score")

      tier =
        ~s(CASE WHEN #{row_score} > $1 THEN $2::text ELSE ) <>
          ~s(CASE WHEN #{row_score} > $3 THEN $4::text ELSE $5::text END END)

      assert %{
               params: [
                 {:value, 10},
                 {:value, "gold"},
                 {:value, 5},
                 {:value, "silver"},
                 {:value, "bronze"},
                 {:value, "gold"}
               ],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| AND "score" > #{row_score}::float8 AND #{tier} = $6) ORDER BY|
             )
    end

    test "keeps nil's meaning in a membership on a derived value", %{mapping: mapping} do
      tier =
        ~s(CASE WHEN "score" > $1 THEN $2::text ELSE ) <>
          ~s(CASE WHEN "score" > $3 THEN $4::text ELSE $5::text END END)

      expected_params = [
        {:value, 10},
        {:value, "gold"},
        {:value, 5},
        {:value, "silver"},
        {:value, "bronze"},
        {:value, ["gold"]}
      ]

      member_term =
        Module39
        |> filter(tier in [:gold, nil])
        |> Stage.normalize()

      non_member_term =
        Module39
        |> filter(tier not in [:gold, nil])
        |> Stage.normalize()

      assert %{params: member_params, sql: member_sql} = compile(member_term, mapping)
      assert member_params == expected_params

      assert String.contains?(
               member_sql,
               ~s| WHERE (#{tier} = ANY($6) OR #{tier} IS NULL) ORDER BY|
             )

      assert %{params: non_member_params, sql: non_member_sql} = compile(non_member_term, mapping)
      assert non_member_params == expected_params

      assert String.contains?(
               non_member_sql,
               ~s| WHERE (#{tier} != ALL($6) AND #{tier} IS NOT NULL) ORDER BY|
             )
    end

    test "binds a derived sort's slots after the policy's", %{mapping: mapping} do
      term =
        Module39
        |> sort(tier: :desc)
        |> Stage.normalize()

      policy = %{rules: [%{predicates: [{:score, :>, 0}], to: nil, via: nil}]}

      tier =
        ~s(CASE WHEN "score" > $2 THEN $3::text ELSE ) <>
          ~s(CASE WHEN "score" > $4 THEN $5::text ELSE $6::text END END)

      assert %{
               params: [
                 {:value, 0},
                 {:value, 10},
                 {:value, "gold"},
                 {:value, 5},
                 {:value, "silver"},
                 {:value, "bronze"}
               ],
               sql: sql
             } = compile(term, mapping, policy)

      assert String.ends_with?(
               sql,
               ~s| WHERE "score" > $1 ORDER BY array_position(ARRAY['gold', 'silver', 'bronze'], #{tier}) DESC, "id" ASC|
             )
    end

    test "sorts a to-many include by a derived field computed on each related row", %{
      mapping: mapping
    } do
      term =
        Module39
        |> narrowed_include(:mentors, fn related_query -> sort(related_query, active: :desc) end)
        |> Stage.normalize()

      assert %{params: [{:value, 0}, {:value, 3}, {:value, 0}, {:value, 3}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|ORDER BY COALESCE(("score" > $1 AND "score" < $2), false) DESC, "id" ASC) AS "$i1"|
             )

      assert String.contains?(
               sql,
               ~s|ORDER BY COALESCE(("$i1"."score" > $3 AND "$i1"."score" < $4), false) DESC, | <>
                 ~s|"$i1"."id" ASC), '[]'::jsonb|
             )
    end
  end

  describe "compile/2 - derived includes" do
    setup do
      put_derived_definitions([Module32, Module33, Module37, Module38, Module40])

      mapping =
        Mapper.derive!(
          [
            Module1,
            Module2,
            Module32,
            Module33,
            Module34,
            Module37,
            Module38,
            Module39,
            Module40,
            Module41
          ],
          []
        )

      [mapping: mapping]
    end

    defp message_pairs(quoted_alias) do
      Enum.map_join(
        ~w(id body position channel_id created_at server_created_at server_updated_at updated_at $revisions),
        ", ",
        &~s|'#{&1}', "#{quoted_alias}"."#{&1}"|
      )
    end

    defp pinned_message_pairs(quoted_alias) do
      Enum.map_join(
        ~w(id pinned author_id channel_id created_at server_created_at server_updated_at updated_at $revisions),
        ", ",
        &~s|'#{&1}', "#{quoted_alias}"."#{&1}"|
      )
    end

    test "selects a derived value as a column", %{mapping: mapping} do
      term =
        Module32
        |> include(message_count)
        |> Stage.normalize()

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s|SELECT "id", "name", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions", | <>
                   ~s|(SELECT count(*) FROM #{table(Module33)} AS "$s1" | <>
                   ~s|WHERE "$s1"."channel_id" = "test_fixtures_entity_module32"."id") AS "message_count" | <>
                   ~s|FROM #{table(Module32)} ORDER BY "id" ASC|
             }
    end

    test "embeds a derived set's rows in its order, its bounds applied", %{mapping: mapping} do
      term =
        Module32
        |> include(recent_messages)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|, (SELECT COALESCE(jsonb_agg(jsonb_build_object(#{message_pairs("$i1")}) | <>
                 ~s|ORDER BY "$i1"."position" DESC, "$i1"."id" ASC), '[]'::jsonb) | <>
                 ~s|FROM (SELECT "$s1".* FROM #{table(Module33)} AS "$s1" | <>
                 ~s|WHERE "$s1"."channel_id" = "test_fixtures_entity_module32"."id" | <>
                 ~s|ORDER BY "position" DESC, "id" ASC LIMIT 2) AS "$i1") AS "recent_messages" FROM|
             )
    end

    test "embeds a derived field's row, the first in its order", %{mapping: mapping} do
      term =
        Module32
        |> include(first_message)
        |> Stage.normalize()

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|, (SELECT jsonb_build_object(#{message_pairs("$i1")}) | <>
                 ~s|FROM (SELECT "$s1".* FROM #{table(Module33)} AS "$s1" | <>
                 ~s|WHERE "$s1"."channel_id" = "test_fixtures_entity_module32"."id" | <>
                 ~s|ORDER BY "position" ASC, "id" ASC LIMIT 1) AS "$i1") AS "first_message" FROM|
             )
    end

    test "embeds what a derived set's definition includes beside what the include asks for", %{
      mapping: mapping
    } do
      term =
        Module37
        |> include(authored_messages.channel)
        |> Stage.normalize()

      author =
        ~s|(SELECT jsonb_build_object('id', "$i2"."id", 'created_at', "$i2"."created_at", | <>
          ~s|'server_created_at', "$i2"."server_created_at", | <>
          ~s|'server_updated_at', "$i2"."server_updated_at", | <>
          ~s|'updated_at', "$i2"."updated_at", '$revisions', "$i2"."$revisions") | <>
          ~s|FROM #{table(Module1)} AS "$i2" WHERE "$i2"."id" = "$i1"."author_id")|

      channel =
        ~s|(SELECT jsonb_build_object('id', "$i3"."id", 'last_read_at', "$i3"."last_read_at", | <>
          ~s|'name', "$i3"."name", 'created_at', "$i3"."created_at", | <>
          ~s|'server_created_at', "$i3"."server_created_at", | <>
          ~s|'server_updated_at', "$i3"."server_updated_at", | <>
          ~s|'updated_at', "$i3"."updated_at", '$revisions', "$i3"."$revisions") | <>
          ~s|FROM #{table(Module37)} AS "$i3" WHERE "$i3"."id" = "$i1"."channel_id")|

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|jsonb_build_object(#{pinned_message_pairs("$i1")}, | <>
                 ~s|'author', #{author}, 'channel', #{channel}) ORDER BY "$i1"."id" ASC|
             )
    end

    test "embeds the rows of the branch an if chooses, and none for nil", %{mapping: mapping} do
      term =
        Module37
        |> include([nothing, picked])
        |> Stage.normalize()

      taken_rows =
        ~s|(SELECT COALESCE(jsonb_agg(jsonb_build_object(#{pinned_message_pairs("$i1")}) | <>
          ~s|ORDER BY "$i1"."id" ASC), '[]'::jsonb) | <>
          ~s|FROM (SELECT "$s1".* FROM #{table(Module38)} AS "$s1" | <>
          ~s|WHERE "$s1"."channel_id" = "test_fixtures_entity_module37"."id" | <>
          ~s|ORDER BY "id" ASC LIMIT 1) AS "$i1")|

      assert %{params: [{:value, "general"}, {:value, "general"}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(sql, ~s|, '[]'::jsonb AS "nothing", |)

      assert String.contains?(
               sql,
               ~s|, CASE WHEN ("test_fixtures_entity_module37"."name_$sort" = $1 | <>
                 ~s|AND "test_fixtures_entity_module37"."name" = $2) | <>
                 ~s|THEN #{taken_rows} ELSE (SELECT COALESCE(jsonb_agg(jsonb_build_object(#{pinned_message_pairs("$i2")})|
             )
    end

    test "embeds the row a skip leaves first, and no row for nil", %{mapping: mapping} do
      term =
        Module40
        |> include([no_note, second_note])
        |> Stage.normalize()

      note_pairs =
        Enum.map_join(
          ~w(id public team_id created_at server_created_at server_updated_at updated_at $revisions),
          ", ",
          &~s|'#{&1}', "$i1"."#{&1}"|
        )

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|, NULL AS "no_note", (SELECT jsonb_build_object(#{note_pairs}) | <>
                 ~s|FROM (SELECT "$s1".* FROM #{table(Module41)} AS "$s1" | <>
                 ~s|WHERE "$s1"."team_id" = "test_fixtures_entity_module40"."id" | <>
                 ~s|ORDER BY "id" ASC LIMIT 1 OFFSET 1) AS "$i1") AS "second_note" FROM|
             )
    end

    test "computes a derived value included under a related row on that row", %{
      mapping: mapping
    } do
      term =
        Module32
        |> include(messages.later_count)
        |> Stage.normalize()

      later_count =
        ~s|(SELECT count(*) FROM #{table(Module33)} AS "$s1" | <>
          ~s|WHERE EXISTS (SELECT 1 FROM #{table(Module32)} AS "$s1_1" | <>
          ~s|WHERE "$s1_1"."id" = "$i1"."channel_id" AND "$s1"."channel_id" = "$s1_1"."id") | <>
          ~s|AND "position" > "$i1"."position")|

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|jsonb_build_object(#{message_pairs("$i1")}, 'later_count', #{later_count}) ORDER BY|
             )
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
                 ~s(SELECT "id", "b_id", "c_id", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions" ) <>
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

    test "carries an acting user expression into a hop's read policy" do
      mapping = path_mapping([Module14, PathSource2, PathTarget2])
      term = path_term(PathSource2, [{[:target, :name], "x"}])
      rules = Policy.build(PathSource2)[:read]

      assert %{params: [{:value, "x"}], sql: sql} =
               compile(term, mapping, %{actor_sql: ~s|"$x"."$user"|, rules: rules})

      assert String.contains?(
               sql,
               ~s|WHERE "$p1"."id" = "#{Mapper.table_name(PathSource2)}"."target_id" | <>
                 ~s|AND "owner_id" = "$x"."$user") = $1|
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
        |> narrowed_include(:a, &Stage.filter(&1, [{[:b, :a], true}]))
        |> Stage.normalize()

      b_a = hop(1, Module2, ~s("$p1"."a"), ~s("$t1"."b_id"))

      assert %{params: [{:value, true}], sql: sql} = compile(term, mapping)
      assert String.contains?(sql, ~s| AND #{b_a} = $1|)
    end
  end

  describe "compile/2 - quantifiers" do
    test "compiles none and all through a set over the rows every path reaches" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])
      none_term = path_term(Module26, none: {[:messages, :labels], [name: "u"]})
      all_term = path_term(Module26, all: {[:messages, :labels], [name: "u"]})

      labels =
        ~s|EXISTS (SELECT 1 FROM #{table(Module28)} AS "$s1_1" | <>
          ~s|WHERE "$s1_1"."channel_id" = "test_fixtures_entity_module26"."id" | <>
          ~s|AND "$q1"."id" IN (SELECT "$sj1"."target_id" | <>
          ~s|FROM "hologram_data"."test_fixtures_entity_module28_labels_$join" AS "$sj1" | <>
          ~s|WHERE "$sj1"."source_id" = "$s1_1"."id"))|

      assert %{params: [{:value, "u"}, {:value, "u"}], sql: none_sql} =
               compile(none_term, mapping)

      assert %{params: [{:value, "u"}, {:value, "u"}], sql: all_sql} = compile(all_term, mapping)

      assert String.contains?(
               none_sql,
               ~s| WHERE NOT EXISTS (SELECT 1 FROM #{table(Module29)} AS "$q1" | <>
                 ~s|WHERE #{labels} AND ("name_$sort" = $1 AND "name" = $2)) ORDER BY|
             )

      assert String.contains?(
               all_sql,
               ~s| WHERE NOT EXISTS (SELECT 1 FROM #{table(Module29)} AS "$q1" | <>
                 ~s|WHERE #{labels} AND (("name_$sort" = $1 AND "name" = $2)) IS NOT TRUE) ORDER BY|
             )
    end

    test "reads a source going first through a to-many or an inverse holding one row" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])
      to_many_term = path_term(Module28, any: {[:labels, :messages], [body: "hi"]})
      inverse_term = path_term(Module26, any: {[:topic, :channel, :messages], [body: "hi"]})

      labels =
        ~s|EXISTS (SELECT 1 FROM #{table(Module29)} AS "$s1_1" | <>
          ~s|WHERE "$s1_1"."id" IN (SELECT "$sj1"."target_id" | <>
          ~s|FROM "hologram_data"."test_fixtures_entity_module28_labels_$join" AS "$sj1" | <>
          ~s|WHERE "$sj1"."source_id" = "test_fixtures_entity_module28"."id") | <>
          ~s|AND "$q1"."id" IN (SELECT "$sj1"."source_id" | <>
          ~s|FROM "hologram_data"."test_fixtures_entity_module28_labels_$join" AS "$sj1" | <>
          ~s|WHERE "$sj1"."target_id" = "$s1_1"."id"))|

      topic =
        ~s|EXISTS (SELECT 1 FROM #{table(Module26)} AS "$s1_2" | <>
          ~s|WHERE EXISTS (SELECT 1 FROM #{table(Module27)} AS "$s1_1" | <>
          ~s|WHERE "$s1_1"."channel_id" = "test_fixtures_entity_module26"."id" | <>
          ~s|AND "$s1_2"."id" = "$s1_1"."channel_id") | <>
          ~s|AND "$q1"."channel_id" = "$s1_2"."id")|

      assert %{params: [{:value, "hi"}, {:value, "hi"}], sql: to_many_sql} =
               compile(to_many_term, mapping)

      assert %{params: [{:value, "hi"}, {:value, "hi"}], sql: inverse_sql} =
               compile(inverse_term, mapping)

      body = ~s|("body_$sort" = $1 AND "body" = $2)|

      assert String.contains?(to_many_sql, ~s| WHERE #{labels} AND #{body}) ORDER BY|)
      assert String.contains?(inverse_sql, ~s| WHERE #{topic} AND #{body}) ORDER BY|)
    end

    test "compiles any through a set to nested EXISTS" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])
      term = path_term(Module26, any: {[:messages, :labels], [name: "u"]})

      labels =
        ~s|"$q1"."id" IN (SELECT "$sj1"."target_id" | <>
          ~s|FROM "hologram_data"."test_fixtures_entity_module28_labels_$join" AS "$sj1" | <>
          ~s|WHERE "$sj1"."source_id" = "$s1_1"."id")|

      messages =
        ~s|EXISTS (SELECT 1 FROM #{table(Module28)} AS "$s1_1" | <>
          ~s|WHERE "$s1_1"."channel_id" = "test_fixtures_entity_module26"."id" AND #{labels})|

      assert %{params: [{:value, "u"}, {:value, "u"}], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE EXISTS (SELECT 1 FROM #{table(Module29)} AS "$q1" | <>
                 ~s|WHERE #{messages} AND ("name_$sort" = $1 AND "name" = $2)) ORDER BY|
             )
    end

    test "compiles any over an inverse of a to-one to an EXISTS on the related rows' reference" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])
      term = path_term(Module26, any: {[:messages], [body: "hi"]})

      assert %{params: [{:value, "hi"}, {:value, "hi"}], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE EXISTS (SELECT 1 FROM #{table(Module28)} AS "$q1" | <>
                 ~s|WHERE "$q1"."channel_id" = "test_fixtures_entity_module26"."id" | <>
                 ~s|AND ("body_$sort" = $1 AND "body" = $2)) ORDER BY|
             )
    end

    test "compiles any with no condition to an EXISTS on the membership alone" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])
      term = path_term(Module26, any: {[:messages], []})

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE EXISTS (SELECT 1 FROM #{table(Module28)} AS "$q1" | <>
                 ~s|WHERE "$q1"."channel_id" = "test_fixtures_entity_module26"."id") ORDER BY|
             )
    end

    test "compiles any over a stored to-many through its join table" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])
      term = path_term(Module28, any: {[:labels], [name: "urgent"]})

      assert %{params: [{:value, "urgent"}, {:value, "urgent"}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE EXISTS (SELECT 1 FROM #{table(Module29)} AS "$q1" | <>
                 ~s|WHERE "$q1"."id" IN (SELECT "$qj1"."target_id" | <>
                 ~s|FROM "hologram_data"."test_fixtures_entity_module28_labels_$join" AS "$qj1" | <>
                 ~s|WHERE "$qj1"."source_id" = "test_fixtures_entity_module28"."id") | <>
                 ~s|AND ("name_$sort" = $1 AND "name" = $2)) ORDER BY|
             )
    end

    test "compiles none to a NOT EXISTS" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])
      term = path_term(Module26, none: {[:messages], [body: "hi"]})

      assert %{sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE NOT EXISTS (SELECT 1 FROM #{table(Module28)} AS "$q1" | <>
                 ~s|WHERE "$q1"."channel_id" = "test_fixtures_entity_module26"."id" | <>
                 ~s|AND ("body_$sort" = $1 AND "body" = $2)) ORDER BY|
             )
    end

    # A comparison with NULL is unknown in SQL, and NOT of unknown is unknown - the row would pass as
    # no counterexample, where every other tier counts it against all.
    test "compiles all to a NOT EXISTS of the related rows its condition is not true of" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])
      term = path_term(Module29, all: {[:messages], [position: {:>, 1}, body: "x"]})

      assert %{params: [{:value, "x"}, {:value, "x"}, {:value, 1}], sql: sql} =
               compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE NOT EXISTS (SELECT 1 FROM #{table(Module28)} AS "$q1" | <>
                 ~s|WHERE "$q1"."id" IN (SELECT "$qj1"."source_id" | <>
                 ~s|FROM "hologram_data"."test_fixtures_entity_module28_labels_$join" AS "$qj1" | <>
                 ~s|WHERE "$qj1"."target_id" = "test_fixtures_entity_module29"."id") | <>
                 ~s|AND (("body_$sort" = $1 AND "body" = $2) AND "position" > $3) IS NOT TRUE) ORDER BY|
             )
    end

    test "compiles a source through a to-one to a membership on the related row's id, and qualifies a name of the row above" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])

      term =
        path_term(Module28,
          any: {[:channel, :messages], [position: {:>, {:attribute, {:outer, 1, :position}}}]}
        )

      channel_id =
        hop(1, Module26, ~s("$p1"."id"), ~s("test_fixtures_entity_module28"."channel_id"))

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE EXISTS (SELECT 1 FROM #{table(Module28)} AS "$q1" | <>
                 ~s|WHERE "$q1"."channel_id" = #{channel_id} | <>
                 ~s|AND "position" > "test_fixtures_entity_module28"."position") ORDER BY|
             )
    end

    test "compares a string with one of the row above by both sort-key pairs" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])

      term =
        path_term(Module26, any: {[:messages], [body: {:<, {:attribute, {:outer, 1, :name}}}]})

      assert %{sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|AND ("body_$sort", "body") < | <>
                 ~s|("test_fixtures_entity_module26"."name_$sort", "test_fixtures_entity_module26"."name"))|
             )
    end

    test "nests a quantifier under the one around it, correlated on its alias" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])

      term =
        path_term(Module26,
          any: {[:messages], [any: {[:labels], [name: {:attribute, {:outer, 2, :name}}]}]}
        )

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|AND EXISTS (SELECT 1 FROM #{table(Module29)} AS "$q2" | <>
                 ~s|WHERE "$q2"."id" IN (SELECT "$qj2"."target_id" | <>
                 ~s|FROM "hologram_data"."test_fixtures_entity_module28_labels_$join" AS "$qj2" | <>
                 ~s|WHERE "$qj2"."source_id" = "$q1"."id") | <>
                 ~s|AND "name" IS NOT DISTINCT FROM "test_fixtures_entity_module26"."name"))|
             )
    end

    test "reads a source of a row above on that row's alias" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])

      term =
        path_term(Module28,
          any:
            {[:labels], [any: {{:outer, 1, [:labels]}, [name: {:attribute, {:outer, 1, :name}}]}]}
        )

      assert %{sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|WHERE "$qj2"."source_id" = "test_fixtures_entity_module28"."id")|
             )
    end

    test "qualifies an attribute of the row above on the left" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])
      term = path_term(Module26, any: {[:messages], [{{:outer, 1, :name}, "general"}]})

      assert %{params: [{:value, "general"}], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|AND "test_fixtures_entity_module26"."name" = $1)|
             )
    end

    test "reads a path of the row above on that row, on either side, siblings sharing an alias" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])

      term =
        path_term(Module28,
          any: {[:labels], [name: {:attribute, {:outer, 1, [:channel, :name]}}]},
          any: {[:labels], [{{:outer, 1, [:channel, :name]}, "g"}]}
        )

      channel_name =
        hop(1, Module26, ~s("$p1"."name"), ~s("test_fixtures_entity_module28"."channel_id"))

      membership =
        ~s|"$q1"."id" IN (SELECT "$qj1"."target_id" | <>
          ~s|FROM "hologram_data"."test_fixtures_entity_module28_labels_$join" AS "$qj1" | <>
          ~s|WHERE "$qj1"."source_id" = "test_fixtures_entity_module28"."id")|

      assert %{params: [{:value, "g"}], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s| WHERE EXISTS (SELECT 1 FROM #{table(Module29)} AS "$q1" WHERE #{membership} | <>
                 ~s|AND "name" IS NOT DISTINCT FROM #{channel_name}) | <>
                 ~s|AND EXISTS (SELECT 1 FROM #{table(Module29)} AS "$q1" WHERE #{membership} | <>
                 ~s|AND #{channel_name} = $1) ORDER BY|
             )
    end

    test "correlates a quantifier in an include's filter on the include's alias" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])

      term =
        Module26
        |> narrowed_include(:messages, &Stage.filter(&1, any: {[:labels], [name: "u"]}))
        |> Stage.normalize()

      assert %{params: [{:value, "u"}, {:value, "u"}], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|AND EXISTS (SELECT 1 FROM #{table(Module29)} AS "$q1" | <>
                 ~s|WHERE "$q1"."id" IN (SELECT "$qj1"."target_id" | <>
                 ~s|FROM "hologram_data"."test_fixtures_entity_module28_labels_$join" AS "$qj1" | <>
                 ~s|WHERE "$qj1"."source_id" = "$t1"."id") AND ("name_$sort" = $1 AND "name" = $2))|
             )
    end

    test "numbers the slots inside a quantifier and around it in the order they are written" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])

      term =
        path_term(Module28,
          body: "a",
          any: {[:channel, :messages], [body: "b"]},
          position: 3
        )

      assert %{
               params: [{:value, "b"}, {:value, "b"}, {:value, "a"}, {:value, "a"}, {:value, 3}],
               sql: sql
             } = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|AND ("body_$sort" = $1 AND "body" = $2)) | <>
                 ~s|AND ("body_$sort" = $3 AND "body" = $4) AND "position" = $5 ORDER BY|
             )
    end

    test "applies the related type's read policy inside the subquery" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])
      term = path_term(Module26, any: {[:messages], [position: 1]})
      policy = %{anonymous?: true, rules: Policy.build(Module26).read}

      assert %{params: [{:value, "hidden"}, {:value, 1}], sql: sql} =
               compile(term, mapping, policy)

      assert String.contains?(
               sql,
               ~s|WHERE "$q1"."channel_id" = "test_fixtures_entity_module26"."id" | <>
                 ~s|AND "body" != $1 AND "position" = $2)|
             )
    end
  end

  describe "compile/2 - quantifiers in policy rules" do
    defmodule RuleMessage do
      use Hologram.Entity

      attribute :body, :string

      relationship :author, Module14, optional: true
      relationship :channel, Hologram.DB.QueryCompilerTest.RuleChannel, optional: true
      relationship :reactions, [Hologram.DB.QueryCompilerTest.RuleReaction], inverse: message
      relationship :thread, Hologram.DB.QueryCompilerTest.RuleThread, optional: true

      allow :read, when: body != "hidden"
    end

    defmodule RuleReaction do
      use Hologram.Entity

      attribute :kind, :string

      relationship :message, RuleMessage, optional: true

      allow :read
    end

    defmodule RuleChannel do
      use Hologram.Entity

      attribute :name, :string

      relationship :messages, [RuleMessage], inverse: channel
      relationship :org, Hologram.DB.QueryCompilerTest.RuleOrg, optional: true

      derived :first_messages, [RuleMessage], fn messages -> take(messages, 1) end

      allow :read, when: any(message <- messages, message.body == name)
    end

    defmodule RuleOrg do
      use Hologram.Entity

      relationship :channels, [RuleChannel], inverse: org
      relationship :threads, [Hologram.DB.QueryCompilerTest.RuleThread], inverse: org

      allow :read
    end

    defmodule RuleThread do
      use Hologram.Entity

      relationship :messages, [RuleMessage], inverse: thread
      relationship :org, RuleOrg, optional: true

      allow :read, when: any(reaction <- messages.reactions, reaction.kind == "x")
    end

    defmodule RulePost do
      use Hologram.Entity

      relationship :channel, RuleChannel, optional: true

      allow :read, via: channel
    end

    defp rule_mapping do
      path_mapping([
        Module14,
        RuleChannel,
        RuleMessage,
        RuleOrg,
        RulePost,
        RuleReaction,
        RuleThread
      ])
    end

    defp rules(predicates) do
      [%{predicates: Stage.predicate_triples!(RuleChannel, predicates), to: nil, via: nil}]
    end

    # A policy decides by the rows as stored, so the set a rule's quantifier reads applies no read
    # policy even inside a policied statement - the hidden message counts.
    test "reads the set of a rule's quantifier raw" do
      term = Stage.normalize(RuleChannel)
      policy = %{rules: rules(any: {[:messages], [body: "x"]})}

      assert %{params: [{:value, "x"}, {:value, "x"}], sql: sql} =
               compile(term, rule_mapping(), policy)

      assert String.contains?(
               sql,
               ~s| WHERE EXISTS (SELECT 1 FROM #{table(RuleMessage)} AS "$q1" | <>
                 ~s|WHERE "$q1"."channel_id" = "#{Mapper.table_name(RuleChannel)}"."id" | <>
                 ~s|AND ("body_$sort" = $1 AND "body" = $2)) ORDER BY|
             )
    end

    # The hidden message counts inside a derived set as well.
    test "reads a derived set of a rule's quantifier raw" do
      put_derived_definitions([RuleChannel])

      term = Stage.normalize(RuleChannel)
      policy = %{rules: rules(any: {[:first_messages], [body: "x"]})}

      first_messages =
        ~s|SELECT "$s2"."id" FROM #{table(RuleMessage)} AS "$s2" | <>
          ~s|WHERE "$s2"."channel_id" = "#{Mapper.table_name(RuleChannel)}"."id" | <>
          ~s|ORDER BY "id" ASC LIMIT 1|

      assert %{params: [{:value, "x"}, {:value, "x"}], sql: sql} =
               compile(term, rule_mapping(), policy)

      assert String.contains?(
               sql,
               ~s| WHERE EXISTS (SELECT 1 FROM #{table(RuleMessage)} AS "$q1" | <>
                 ~s|WHERE "$q1"."id" IN (#{first_messages}) AND ("body_$sort" = $1 AND "body" = $2)) ORDER BY|
             )
    end

    test "compiles none and all in a rule" do
      term = Stage.normalize(RuleChannel)
      none_policy = %{rules: rules(none: {[:messages], [body: "x"]})}
      all_policy = %{rules: rules(all: {[:messages], [body: "x"]})}

      messages =
        ~s|SELECT 1 FROM #{table(RuleMessage)} AS "$q1" | <>
          ~s|WHERE "$q1"."channel_id" = "#{Mapper.table_name(RuleChannel)}"."id"|

      assert %{params: [{:value, "x"}, {:value, "x"}], sql: none_sql} =
               compile(term, rule_mapping(), none_policy)

      assert %{params: [{:value, "x"}, {:value, "x"}], sql: all_sql} =
               compile(term, rule_mapping(), all_policy)

      assert String.contains?(
               none_sql,
               ~s| WHERE NOT EXISTS (#{messages} AND ("body_$sort" = $1 AND "body" = $2)) ORDER BY|
             )

      assert String.contains?(
               all_sql,
               ~s| WHERE NOT EXISTS (#{messages} AND (("body_$sort" = $1 AND "body" = $2)) IS NOT TRUE) ORDER BY|
             )
    end

    test "binds the actor slot inside a rule's quantifier" do
      term = Stage.normalize(RuleChannel)
      policy = %{rules: rules(any: {[:messages], [author_id: {:actor}]})}

      assert %{params: [:actor], sql: sql} = compile(term, rule_mapping(), policy)
      assert String.contains?(sql, ~s|AND "author_id" = $1) ORDER BY|)
    end

    test "reads the rule's row from inside its quantifier" do
      term = Stage.normalize(RuleChannel)
      policy = %{rules: Policy.build(RuleChannel)[:read]}

      assert %{params: [], sql: sql} = compile(term, rule_mapping(), policy)

      assert String.contains?(
               sql,
               ~s|"$q1"."channel_id" = "#{Mapper.table_name(RuleChannel)}"."id" | <>
                 ~s|AND "body" IS NOT DISTINCT FROM "#{Mapper.table_name(RuleChannel)}"."name") ORDER BY|
             )
    end

    test "reads the delegation's row from inside the delegated rule's quantifier" do
      term = Stage.normalize(RulePost)
      policy = %{rules: Policy.build(RulePost)[:read]}

      assert %{params: [], sql: sql} = compile(term, rule_mapping(), policy)

      assert String.contains?(
               sql,
               ~s|WHERE "$d1"."id" = "#{Mapper.table_name(RulePost)}"."channel_id" | <>
                 ~s|AND EXISTS (SELECT 1 FROM #{table(RuleMessage)} AS "$q1" | <>
                 ~s|WHERE "$q1"."channel_id" = "$d1"."id" AND "body" IS NOT DISTINCT FROM "$d1"."name"))|
             )
    end

    # The channel's read rule is read inside the authored quantifier's subquery, on its row "$q1" -
    # so the rule's own quantifier takes the next alias, or it would read its own row where it means
    # the channel.
    test "nests a quantified read policy past the quantifier it is read inside" do
      term = path_term(RuleOrg, any: {[:channels], []})
      policy = %{rules: Policy.build(RuleOrg)[:read]}

      assert %{params: [], sql: sql} = compile(term, rule_mapping(), policy)

      assert String.contains?(
               sql,
               ~s|WHERE "$q1"."org_id" = "#{Mapper.table_name(RuleOrg)}"."id" | <>
                 ~s|AND EXISTS (SELECT 1 FROM #{table(RuleMessage)} AS "$q2" | <>
                 ~s|WHERE "$q2"."channel_id" = "$q1"."id" AND "body" IS NOT DISTINCT FROM "$q1"."name"))|
             )
    end

    # Nobody is the actor, so nobody wrote any message - the rule admits no row.
    test "drops an anonymous rule whose any names the actor" do
      term = Stage.normalize(RuleChannel)
      policy = %{anonymous?: true, rules: rules(any: {[:messages], [author_id: {:actor}]})}

      assert %{params: [], sql: sql} = compile(term, rule_mapping(), policy)
      assert String.contains?(sql, ~s| WHERE FALSE ORDER BY|)
    end

    test "keeps the alternative of an anonymous any's condition that names no actor" do
      term = Stage.normalize(RuleChannel)

      predicates = [any: {[:messages], [or: [[author_id: {:actor}], [body: "x"]]]}]
      policy = %{anonymous?: true, rules: rules(predicates)}

      assert %{params: [{:value, "x"}, {:value, "x"}], sql: sql} =
               compile(term, rule_mapping(), policy)

      assert String.contains?(
               sql,
               ~s| WHERE EXISTS (SELECT 1 FROM #{table(RuleMessage)} AS "$q1" | <>
                 ~s|WHERE "$q1"."channel_id" = "#{Mapper.table_name(RuleChannel)}"."id" | <>
                 ~s|AND ("body_$sort" = $1 AND "body" = $2)) ORDER BY|
             )
    end

    # A none or an all asking about the actor asks about nobody, which grants nothing - even when
    # only one alternative of its condition names the actor.
    test "drops an anonymous rule whose none or all names the actor" do
      term = Stage.normalize(RuleChannel)
      condition = [or: [[author_id: {:actor}], [body: "x"]]]
      none_policy = %{anonymous?: true, rules: rules(none: {[:messages], condition})}
      all_policy = %{anonymous?: true, rules: rules(all: {[:messages], condition})}

      assert %{params: [], sql: none_sql} = compile(term, rule_mapping(), none_policy)
      assert %{params: [], sql: all_sql} = compile(term, rule_mapping(), all_policy)

      assert String.contains?(none_sql, ~s| WHERE FALSE ORDER BY|)
      assert String.contains?(all_sql, ~s| WHERE FALSE ORDER BY|)
    end

    # The nested none asks about nobody, so its alternative is false and the other one answers.
    test "folds an anonymous none nested in an any's alternative" do
      term = Stage.normalize(RuleChannel)

      predicates = [
        any: {[:messages], [or: [[none: {[:reactions], [message_id: {:actor}]}], [body: "x"]]]}
      ]

      policy = %{anonymous?: true, rules: rules(predicates)}

      assert %{params: [{:value, "x"}, {:value, "x"}], sql: sql} =
               compile(term, rule_mapping(), policy)

      assert String.contains?(
               sql,
               ~s| WHERE EXISTS (SELECT 1 FROM #{table(RuleMessage)} AS "$q1" | <>
                 ~s|WHERE "$q1"."channel_id" = "#{Mapper.table_name(RuleChannel)}"."id" | <>
                 ~s|AND ("body_$sort" = $1 AND "body" = $2)) ORDER BY|
             )
    end

    # The nested any names the actor in one alternative of the none's condition, so the none asks
    # about nobody whatever its other alternative says.
    test "drops an anonymous rule whose none names the actor in a nested quantifier" do
      term = Stage.normalize(RuleChannel)

      predicates = [
        none: {[:messages], [or: [[any: {[:reactions], [message_id: {:actor}]}], [body: "x"]]]}
      ]

      policy = %{anonymous?: true, rules: rules(predicates)}

      assert %{params: [], sql: sql} = compile(term, rule_mapping(), policy)
      assert String.contains?(sql, ~s| WHERE FALSE ORDER BY|)
    end

    test "keeps the alternative of an anonymous rule beside a none naming the actor" do
      term = Stage.normalize(RuleChannel)

      policy = %{
        anonymous?: true,
        rules: rules(or: [[none: {[:messages], [author_id: {:actor}]}], [name: "x"]])
      }

      assert %{params: [{:value, "x"}, {:value, "x"}], sql: sql} =
               compile(term, rule_mapping(), policy)

      assert String.contains?(sql, ~s| WHERE ("name_$sort" = $1 AND "name" = $2) ORDER BY|)
    end

    test "keeps an anonymous none naming no actor" do
      term = Stage.normalize(RuleChannel)
      policy = %{anonymous?: true, rules: rules(none: {[:messages], [body: "x"]})}

      assert %{params: [{:value, "x"}, {:value, "x"}], sql: sql} =
               compile(term, rule_mapping(), policy)

      assert String.contains?(
               sql,
               ~s| WHERE NOT EXISTS (SELECT 1 FROM #{table(RuleMessage)} AS "$q1" | <>
                 ~s|WHERE "$q1"."channel_id" = "#{Mapper.table_name(RuleChannel)}"."id" | <>
                 ~s|AND ("body_$sort" = $1 AND "body" = $2)) ORDER BY|
             )
    end

    # The thread's read rule is read on the first row of the authored set's chain, "$s1_1" - so the
    # rule's own chain takes the next source alias, or it would read its own link row where it means
    # the thread.
    test "nests a read policy's set chain past the chain it is read on" do
      term = path_term(RuleOrg, any: {[:threads, :messages], []})
      policy = %{rules: Policy.build(RuleOrg)[:read]}

      assert %{sql: sql} = compile(term, rule_mapping(), policy)

      assert String.contains?(
               sql,
               ~s|EXISTS (SELECT 1 FROM #{table(RuleMessage)} AS "$s2_1" | <>
                 ~s|WHERE "$s2_1"."thread_id" = "$s1_1"."id" | <>
                 ~s|AND "$q1"."message_id" = "$s2_1"."id")|
             )
    end
  end

  describe "compile/2 - searches" do
    test "compiles a loose search to a LIKE over the search key, or the sort key without one" do
      mapping = Mapper.derive!([Module2], [])
      term = %{Stage.normalize(Module2) | filter: [{:c, :starts_with, "José"}]}

      assert %{params: [{:value, "jose%"}], sql: sql} = compile(term, mapping)

      assert String.contains?(sql, ~s| WHERE COALESCE("c_$search", "c_$sort") LIKE $1|)
    end

    test "compiles an exact search to a LIKE over the value" do
      mapping = Mapper.derive!([Module2], [])
      term = %{Stage.normalize(Module2) | filter: [{:c, :contains_exact, "Jo"}]}

      assert %{params: [{:value, "%Jo%"}], sql: sql} = compile(term, mapping)

      assert String.contains?(sql, ~s| WHERE "c" LIKE $1|)
    end

    test "compiles a search in a policy rule the way it compiles one in a filter" do
      mapping = Mapper.derive!([Module2], [])
      term = Stage.normalize(Module2)
      rules = [%{predicates: [{:c, :starts_with_exact, "public/"}], to: nil, via: nil}]

      assert %{params: [{:value, "public/%"}], sql: sql} =
               compile(term, mapping, %{rules: rules})

      assert String.contains?(sql, ~s| WHERE "c" LIKE $1|)
    end

    test "escapes % and _ in a term" do
      mapping = Mapper.derive!([Module2], [])
      term = %{Stage.normalize(Module2) | filter: [{:c, :contains_exact, "50%_"}]}

      assert %{params: [{:value, "%50\\%\\_%"}]} = compile(term, mapping)
    end

    test "reads a loose search on a path through the related row's keys" do
      mapping = path_mapping([Module1, Module2, Module3])
      term = path_term(Module3, [{[:b, :c], {:contains, "x"}}])

      assert %{params: [{:value, "%x%"}], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|WHERE (SELECT COALESCE("$p1"."c_$search", "$p1"."c_$sort") FROM #{table(Module2)} AS "$p1" | <>
                 ~s|WHERE "$p1"."id" = "test_fixtures_entity_module3"."b_id") LIKE $1|
             )
    end

    test "compiles a search for another attribute to where its value first occurs" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])
      term = path_term(Module28, body: {:contains, {:attribute, [:channel, :name]}})

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|WHERE strpos(COALESCE("body_$search", "body_$sort"), | <>
                 ~s|(SELECT COALESCE("$p1"."name_$search", "$p1"."name_$sort") FROM #{table(Module26)} AS "$p1" | <>
                 ~s|WHERE "$p1"."id" = "test_fixtures_entity_module28"."channel_id")) > 0|
             )
    end

    test "compiles an exact prefix search for a row above's attribute inside a quantifier" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])

      term =
        path_term(Module26,
          any: {[:messages], [body: {:starts_with_exact, {:attribute, {:outer, 1, :name}}}]}
        )

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|AND strpos("body", "test_fixtures_entity_module26"."name") = 1)|
             )
    end

    test "reads a loose search for a row above's attribute through that row's keys" do
      mapping = path_mapping([Module26, Module27, Module28, Module29])

      term =
        path_term(Module26,
          any: {[:messages], [body: {:contains, {:attribute, {:outer, 1, :name}}}]}
        )

      assert %{params: [], sql: sql} = compile(term, mapping)

      assert String.contains?(
               sql,
               ~s|AND strpos(COALESCE("body_$search", "body_$sort"), | <>
                 ~s|COALESCE("test_fixtures_entity_module26"."name_$search", "test_fixtures_entity_module26"."name_$sort")) > 0)|
             )
    end
  end

  describe "recheck/4" do
    @recheck_mapping Mapper.derive!(
                       [
                         Module14,
                         Module41,
                         PolicyModule1,
                         PolicyModule13,
                         PolicyModule17,
                         PolicyModule18,
                         PolicyModule19,
                         PolicyModule2,
                         PolicyModule26,
                         PolicyModule27,
                         PolicyModule28,
                         PolicyModule29,
                         PolicyModule3,
                         PolicyModule5,
                         PolicyModule6,
                         PolicyModule8,
                         ReadersModule1,
                         ReadersModule10,
                         ReadersModule12,
                         ReadersModule13,
                         ReadersModule15,
                         ReadersModule16,
                         ReadersModule17,
                         ReadersModule18,
                         ReadersModule2,
                         ReadersModule3,
                         ReadersModule4,
                         ReadersModule5,
                         ReadersModule8,
                         ReadersModule9,
                         RoleGrant
                       ],
                       [Role.Module1, Role.Module2]
                     )

    defp recheck_sql(entity_type, anonymous_sql, everyone_sql, readers_sql) do
      table_name = Mapper.table_name(entity_type)

      columns =
        @recheck_mapping
        |> Map.fetch!(entity_type)
        |> Map.fetch!(:columns)
        |> Enum.reject(&Mapper.derived?/1)
        |> Enum.map_join(", ", &~s|"#{&1.name}"|)

      ~s|SELECT * FROM (SELECT #{columns}, "$e"."$everyone", | <>
        ~s|#{anonymous_sql} AS "$anonymous", #{readers_sql} AS "$readers" | <>
        ~s|FROM "hologram_data"."#{table_name}" | <>
        ~s|CROSS JOIN LATERAL (SELECT #{everyone_sql} AS "$everyone" OFFSET 0) AS "$e" | <>
        ~s|WHERE "#{table_name}"."id" = ANY($1::uuid[]) OFFSET 0) AS "$rows" | <>
        ~s|WHERE "$everyone" OR "$anonymous" OR cardinality("$readers") > 0|
    end

    defp tested_readers_sql(condition_sql) do
      ~s|CASE WHEN "$e"."$everyone" THEN '{}'::uuid[] | <>
        ~s|ELSE ARRAY(SELECT DISTINCT "$c"."$reader" | <>
        ~s|FROM (SELECT "$u"."$user" FROM unnest($2::uuid[]) AS "$u"("$user")) AS "$c"("$reader") | <>
        ~s|WHERE #{condition_sql}) END|
    end

    defp listed_readers_sql(candidates_sql, condition_sql) do
      ~s|CASE WHEN "$e"."$everyone" THEN '{}'::uuid[] | <>
        ~s|ELSE ARRAY(SELECT DISTINCT "$c"."$reader" | <>
        ~s|FROM (#{candidates_sql}) AS "$c"("$reader") | <>
        ~s|WHERE ("$c"."$reader" IN | <>
        ~s|(SELECT "$u"."$user" FROM unnest($2::uuid[]) AS "$u"("$user"))) IS TRUE | <>
        ~s|AND #{condition_sql}) END|
    end

    defp readers_table(entity_type), do: ~s|"#{Mapper.table_name(entity_type)}"|

    test "compares a string a rule names by its sort key beside its value" do
      everyone_sql = ~s|(("seat_$sort" = $2 AND "seat" = $3)) IS TRUE|

      assert %{params: [:ids, {:value, "full"}, {:value, "full"}], sql: sql} =
               recheck(PolicyModule18, @recheck_mapping, false)

      assert sql == recheck_sql(PolicyModule18, "FALSE", everyone_sql, "'{}'::uuid[]")
    end

    test "decides a type whose rule admits everyone once per row" do
      assert recheck(PolicyModule3, @recheck_mapping, false) == %{
               params: [:ids],
               sql: recheck_sql(PolicyModule3, "FALSE", "TRUE", "'{}'::uuid[]")
             }
    end

    test "decides a type whose rules answer the same for every user once per row, never NULL" do
      assert recheck(Module41, @recheck_mapping, false) == %{
               params: [:ids, {:value, true}],
               sql: recheck_sql(Module41, "FALSE", ~s|("public" = $2) IS TRUE|, "'{}'::uuid[]")
             }
    end

    test "finds the readers a rule compares the acting user to from the row" do
      assert recheck(ReadersModule2, @recheck_mapping, false) == %{
               params: [:ids, :users],
               sql:
                 recheck_sql(
                   ReadersModule2,
                   "FALSE",
                   "FALSE",
                   listed_readers_sql(~s|SELECT "user_id"|, ~s|"user_id" = "$c"."$reader"|)
                 )
             }
    end

    test "tests every user for a type with a rule that can't list its readers" do
      assert recheck(ReadersModule5, @recheck_mapping, false) == %{
               params: [:ids, :users],
               sql:
                 recheck_sql(
                   ReadersModule5,
                   "FALSE",
                   "FALSE",
                   tested_readers_sql(~s|("owner_id" != "$c"."$reader" OR "owner_id" IS NULL)|)
                 )
             }
    end

    defp candidates_sql(sql) do
      [_sql, candidates_sql] =
        Regex.run(
          ~r/ARRAY\(SELECT DISTINCT "\$c"."\$reader" FROM \((.*)\) AS "\$c"\("\$reader"\) WHERE \("\$c"/,
          sql
        )

      candidates_sql
    end

    defp grant_candidate_sql(roles_slot, type_slot, scope_sql) do
      ~s|SELECT "$rg"."user_id" FROM "hologram_data"."hologram_role_grant" AS "$rg" | <>
        ~s|WHERE "$rg"."role" = ANY($#{roles_slot}::"hologram_data"."hologram_role_grant_role_$enum"[]) | <>
        ~s|AND "$rg"."entity_type" = | <>
        ~s|$#{type_slot}::"hologram_data"."hologram_role_grant_entity_type_$enum" AND #{scope_sql}|
    end

    test "finds the holders of a rule's own and type-wide roles" do
      child = readers_table(PolicyModule1)

      assert %{params: params, sql: sql} = recheck(PolicyModule1, @recheck_mapping, false)

      assert candidates_sql(sql) ==
               "(" <>
                 grant_candidate_sql(
                   8,
                   9,
                   ~s|("$rg"."entity_id" = #{child}."id" OR "$rg"."entity_id" IS NULL)|
                 ) <>
                 ") UNION (" <> grant_candidate_sql(10, 11, ~s|"$rg"."entity_id" IS NULL|) <> ")"

      assert Enum.slice(params, 7, 4) == [
               {:value, ["viewer"]},
               {:value, "Hologram.Test.Fixtures.Policy.Module1"},
               {:value, ["admin"]},
               {:value, "Hologram.Test.Fixtures.Policy.Module2"}
             ]
    end

    test "finds the holders of a role on a related row" do
      assert %{sql: sql} = recheck(PolicyModule13, @recheck_mapping, false)

      assert candidates_sql(sql) ==
               grant_candidate_sql(
                 5,
                 6,
                 ~s|"$rg"."entity_id" = #{readers_table(PolicyModule13)}."parent_id"|
               )
    end

    test "finds the holders of roles on the entity a grant names, and of global roles" do
      grant = readers_table(RoleGrant)

      named_scope =
        ~s|#{grant}."entity_id" IS NOT NULL | <>
          ~s|AND ("$rg"."entity_id" = #{grant}."entity_id" OR "$rg"."entity_id" IS NULL)|

      assert %{sql: sql} = recheck(RoleGrant, @recheck_mapping, false)

      global_sql =
        ~s|SELECT "$rg"."user_id" FROM "hologram_data"."hologram_role_grant" AS "$rg" | <>
          ~s|WHERE "$rg"."role" = ANY($17::"hologram_data"."hologram_role_grant_role_$enum"[]) | <>
          ~s|AND "$rg"."entity_type" IS NULL AND "$rg"."entity_id" IS NULL|

      assert candidates_sql(sql) ==
               ~s|(SELECT "user_id") UNION (| <>
                 grant_candidate_sql(13, 14, named_scope) <>
                 ") UNION ((" <>
                 grant_candidate_sql(15, 16, named_scope) <>
                 ") UNION (" <>
                 global_sql <>
                 ")) UNION (" <>
                 grant_candidate_sql(18, 19, named_scope) <>
                 ")"
    end

    test "finds the readers of a delegation on the row it leads to" do
      assert %{sql: sql} = recheck(ReadersModule4, @recheck_mapping, false)

      assert candidates_sql(sql) ==
               ~s|SELECT "$cd1"."$reader" | <>
                 ~s|FROM "hologram_data"."test_fixtures_policy_readers_module1" AS "$d1" | <>
                 ~s|CROSS JOIN LATERAL (SELECT "$cq1"."$reader" | <>
                 ~s|FROM "hologram_data"."test_fixtures_policy_readers_module2" AS "$q1" | <>
                 ~s|CROSS JOIN LATERAL (SELECT "user_id") AS "$cq1"("$reader") | <>
                 ~s|WHERE "$q1"."project_id" = "$d1"."id") AS "$cd1"("$reader") | <>
                 ~s|WHERE "$d1"."id" = #{readers_table(ReadersModule4)}."project_id"|
    end

    test "follows a path to the row a delegation or a role reference names" do
      chain_sql =
        ~s|(SELECT "$p1"."parent_id" FROM "hologram_data"."test_fixtures_policy_module1" AS "$p1" | <>
          ~s|WHERE "$p1"."id" = #{readers_table(ReadersModule13)}."parent_id")|

      delegation_sql =
        ~s|SELECT "$cd1"."$reader" FROM "hologram_data"."test_fixtures_policy_module2" AS "$d1" | <>
          ~s|CROSS JOIN LATERAL (| <>
          grant_candidate_sql(
            22,
            23,
            ~s|("$rg"."entity_id" = "$d1"."id" OR "$rg"."entity_id" IS NULL)|
          ) <>
          ~s|) AS "$cd1"("$reader") WHERE "$d1"."id" = #{chain_sql}|

      reference_sql = grant_candidate_sql(24, 25, ~s|"$rg"."entity_id" = #{chain_sql}|)

      assert %{sql: sql} = recheck(ReadersModule13, @recheck_mapping, false)

      candidates = candidates_sql(sql)

      assert String.ends_with?(candidates, ~s|(#{delegation_sql}) UNION (#{reference_sql})|)
    end

    test "finds the readers of a delegation to a delegating type two rows away" do
      assert %{sql: sql} = recheck(PolicyModule8, @recheck_mapping, false)

      grants_sql =
        "(" <>
          grant_candidate_sql(
            8,
            9,
            ~s|("$rg"."entity_id" = "$d2"."id" OR "$rg"."entity_id" IS NULL)|
          ) <> ") UNION (" <> grant_candidate_sql(10, 11, ~s|"$rg"."entity_id" IS NULL|) <> ")"

      assert candidates_sql(sql) ==
               ~s|SELECT "$cd1"."$reader" | <>
                 ~s|FROM "hologram_data"."test_fixtures_policy_module5" AS "$d1" | <>
                 ~s|CROSS JOIN LATERAL (SELECT "$cd2"."$reader" | <>
                 ~s|FROM "hologram_data"."test_fixtures_policy_module1" AS "$d2" | <>
                 ~s|CROSS JOIN LATERAL (#{grants_sql}) AS "$cd2"("$reader") | <>
                 ~s|WHERE "$d2"."id" = "$d1"."parent_id") AS "$cd1"("$reader") | <>
                 ~s|WHERE "$d1"."id" = #{readers_table(PolicyModule8)}."parent_id"|
    end

    test "finds the readers of an any over a path from the set the path reaches" do
      assert %{sql: sql} = recheck(ReadersModule3, @recheck_mapping, false)

      assert String.contains?(
               sql,
               ~s|FROM (SELECT "$cq1"."$reader" | <>
                 ~s|FROM "hologram_data"."test_fixtures_policy_readers_module2" AS "$q1" | <>
                 ~s|CROSS JOIN LATERAL (SELECT "user_id") AS "$cq1"("$reader") | <>
                 ~s|WHERE "$q1"."project_id" = (SELECT "$p1"."id" | <>
                 ~s|FROM "hologram_data"."test_fixtures_policy_readers_module1" AS "$p1" | <>
                 ~s|WHERE "$p1"."id" = #{readers_table(ReadersModule3)}."project_id")) | <>
                 ~s|AS "$c"("$reader")|
             )
    end

    test "finds the readers of nested, flattened and outer-row quantifiers and of disjunctions" do
      board = readers_table(ReadersModule8)

      assert %{params: params, sql: sql} = recheck(ReadersModule8, @recheck_mapping, false)

      nested_sql =
        ~s|(SELECT "$cq1"."$reader" | <>
          ~s|FROM "hologram_data"."test_fixtures_policy_readers_module9" AS "$q1" | <>
          ~s|CROSS JOIN LATERAL (SELECT "$cq2"."$reader" | <>
          ~s|FROM "hologram_data"."test_fixtures_policy_readers_module10" AS "$q2" | <>
          ~s|CROSS JOIN LATERAL (SELECT "assignee_id") AS "$cq2"("$reader") | <>
          ~s|WHERE "$q2"."list_id" = "$q1"."id") AS "$cq1"("$reader") | <>
          ~s|WHERE "$q1"."board_id" = #{board}."id")|

      alternatives_sql =
        ~s|(SELECT "$cq1"."$reader" | <>
          ~s|FROM "hologram_data"."test_fixtures_policy_readers_module9" AS "$q1" | <>
          ~s|CROSS JOIN LATERAL ((SELECT "lead_id") UNION (SELECT "deputy_id")) | <>
          ~s|AS "$cq1"("$reader") WHERE "$q1"."board_id" = #{board}."id")|

      flattened_sql =
        ~s|(SELECT "$cq1"."$reader" | <>
          ~s|FROM "hologram_data"."test_fixtures_policy_readers_module10" AS "$q1" | <>
          ~s|CROSS JOIN LATERAL (SELECT "reviewer_id") AS "$cq1"("$reader") | <>
          ~s|WHERE EXISTS (SELECT 1 FROM "hologram_data"."test_fixtures_policy_readers_module9" | <>
          ~s|AS "$s1_1" WHERE "$s1_1"."board_id" = #{board}."id" AND "$q1"."list_id" = "$s1_1"."id"))|

      outer_sql =
        ~s|(SELECT "$cq1"."$reader" | <>
          ~s|FROM "hologram_data"."test_fixtures_policy_readers_module9" AS "$q1" | <>
          ~s|CROSS JOIN LATERAL (SELECT #{board}."owner_id") AS "$cq1"("$reader") | <>
          ~s|WHERE "$q1"."board_id" = #{board}."id")|

      owner_sql = ~s|(SELECT "owner_id")|

      path_sql =
        ~s|(SELECT (SELECT "$p1"."id" FROM "hologram_data"."test_fixtures_entity_module14" | <>
          ~s|AS "$p1" WHERE "$p1"."id" = #{board}."sponsor_id"))|

      derived_sql =
        ~s|(SELECT "$cq1"."$reader" | <>
          ~s|FROM "hologram_data"."test_fixtures_policy_readers_module9" AS "$q1" | <>
          ~s|CROSS JOIN LATERAL (SELECT "$cq2"."$reader" | <>
          ~s|FROM "hologram_data"."test_fixtures_policy_readers_module10" AS "$q2" | <>
          ~s|CROSS JOIN LATERAL (SELECT "watcher_id") AS "$cq2"("$reader") | <>
          ~s|WHERE "$q2"."id" IN (SELECT "$s2"."id" | <>
          ~s|FROM "hologram_data"."test_fixtures_policy_readers_module10" AS "$s2" | <>
          ~s|WHERE "$s2"."list_id" = "$q1"."id" AND "done" = $9)) AS "$cq1"("$reader") | <>
          ~s|WHERE "$q1"."board_id" = #{board}."id")|

      candidates_sql =
        Enum.join(
          [
            nested_sql,
            alternatives_sql,
            flattened_sql,
            outer_sql,
            owner_sql,
            path_sql,
            derived_sql
          ],
          " UNION "
        )

      assert Enum.at(params, 8) == {:value, false}

      assert String.contains?(
               sql,
               ~s|FROM (#{candidates_sql}) AS "$c"("$reader") WHERE ("$c"."$reader" IN|
             )
    end

    test "splits a type's rules into those deciding for everyone and those depending on the user" do
      assert recheck(PolicyModule6, @recheck_mapping, false) == %{
               params: [:ids, :users, {:value, true}],
               sql:
                 recheck_sql(
                   PolicyModule6,
                   "FALSE",
                   ~s|("shared" = $3) IS TRUE|,
                   listed_readers_sql(~s|SELECT "author_id"|, ~s|"author_id" = "$c"."$reader"|)
                 )
             }
    end

    test "still reads the users beside a rule admitting everyone" do
      assert recheck(ReadersModule10, @recheck_mapping, false) == %{
               params: [:ids, :users],
               sql:
                 recheck_sql(
                   ReadersModule10,
                   "FALSE",
                   "TRUE",
                   listed_readers_sql(
                     ~s|SELECT "assignee_id"|,
                     ~s|"assignee_id" = "$c"."$reader"|
                   )
                 )
             }
    end

    test "admits nobody for a type with no read rules, reading no users" do
      assert recheck(PolicyModule19, @recheck_mapping, false) == %{
               params: [:ids],
               sql: recheck_sql(PolicyModule19, "FALSE", "FALSE", "'{}'::uuid[]")
             }
    end

    # A rule answering the same for everyone admits anonymous users too, and $everyone holds its
    # answer, so it isn't decided a second time for them.
    test "decides anonymous users by the rules depending on the user alone, folded for nobody" do
      assert recheck(PolicyModule6, @recheck_mapping, true) == %{
               params: [:ids, :users, {:value, true}],
               sql:
                 recheck_sql(
                   PolicyModule6,
                   "FALSE",
                   ~s|("shared" = $3) IS TRUE|,
                   listed_readers_sql(~s|SELECT "author_id"|, ~s|"author_id" = "$c"."$reader"|)
                 )
             }
    end

    test "admits anonymous users through the part of a rule depending on the user naming nobody" do
      join_table = ~s|"hologram_data"."test_fixtures_policy_readers_module12_lists_$join"|

      assert %{params: params, sql: sql} = recheck(ReadersModule12, @recheck_mapping, true)

      board = readers_table(ReadersModule12)

      assert Enum.at(params, 5) == {:value, true}
      assert length(params) == 20

      assert String.contains?(
               sql,
               ~s|"$e"."$everyone", (EXISTS (SELECT 1 | <>
                 ~s|FROM "hologram_data"."test_fixtures_policy_readers_module9" AS "$q1" | <>
                 ~s|WHERE "$q1"."id" IN (SELECT "$qj1"."target_id" FROM #{join_table} AS "$qj1" | <>
                 ~s|WHERE "$qj1"."source_id" = #{board}."id") AND "open" = $6)) IS TRUE | <>
                 ~s|AS "$anonymous"|
             )
    end

    test "leaves a rule admitting everyone to $everyone, anonymous users included" do
      assert recheck(ReadersModule10, @recheck_mapping, true) == %{
               params: [:ids, :users],
               sql:
                 recheck_sql(
                   ReadersModule10,
                   "FALSE",
                   "TRUE",
                   listed_readers_sql(
                     ~s|SELECT "assignee_id"|,
                     ~s|"assignee_id" = "$c"."$reader"|
                   )
                 )
             }
    end

    test "admits no anonymous user when every rule names the acting user" do
      assert recheck(ReadersModule1, @recheck_mapping, true) == %{
               params: [:ids, :users],
               sql:
                 recheck_sql(
                   ReadersModule1,
                   "FALSE",
                   "FALSE",
                   listed_readers_sql(
                     ~s|SELECT "$cq1"."$reader" | <>
                       ~s|FROM "hologram_data"."test_fixtures_policy_readers_module2" AS "$q1" | <>
                       ~s|CROSS JOIN LATERAL (SELECT "user_id") AS "$cq1"("$reader") | <>
                       ~s|WHERE "$q1"."project_id" = "test_fixtures_policy_readers_module1"."id"|,
                     ~s|EXISTS (SELECT 1 FROM "hologram_data"."test_fixtures_policy_readers_module2" | <>
                       ~s|AS "$q1" WHERE "$q1"."project_id" = "test_fixtures_policy_readers_module1"."id" | <>
                       ~s|AND "user_id" = "$c"."$reader")|
                   )
                 )
             }
    end

    defp verdict_recheck_sql(entity_type, parts) do
      table_name = Mapper.table_name(entity_type)

      columns =
        @recheck_mapping
        |> Map.fetch!(entity_type)
        |> Map.fetch!(:columns)
        |> Enum.reject(&Mapper.derived?/1)
        |> Enum.map_join(", ", &~s|"#{&1.name}"|)

      users_names =
        parts.verdict_users
        |> Enum.with_index(1)
        |> Enum.map_join(", ", fn {_sql, index} -> ~s|"$v"."$verdict_users_#{index}"| end)

      users_columns =
        parts.verdict_users
        |> Enum.with_index(1)
        |> Enum.map_join(", ", fn {sql, index} -> ~s|#{sql} AS "$verdict_users_#{index}"| end)

      ~s|SELECT * FROM (SELECT #{columns}, "$e"."$everyone", | <>
        ~s|#{parts.anonymous} AS "$anonymous", "$r"."$readers", "$e"."$verdict_everyone", | <>
        ~s|ARRAY[#{Enum.join(parts.verdict_anonymous, ", ")}] AS "$verdict_anonymous", | <>
        ~s|#{users_names} | <>
        ~s|FROM "hologram_data"."#{table_name}" | <>
        ~s|CROSS JOIN LATERAL (SELECT #{parts.everyone} AS "$everyone", | <>
        ~s|ARRAY[#{Enum.join(parts.verdict_everyone, ", ")}] AS "$verdict_everyone" | <>
        ~s|OFFSET 0) AS "$e" | <>
        ~s|CROSS JOIN LATERAL (SELECT #{parts.readers} AS "$readers" OFFSET 0) AS "$r" | <>
        ~s|CROSS JOIN LATERAL (SELECT #{users_columns} OFFSET 0) AS "$v" | <>
        ~s|WHERE "#{table_name}"."id" = ANY($1::uuid[]) OFFSET 0) AS "$rows" | <>
        ~s|WHERE "$everyone" OR "$anonymous" OR cardinality("$readers") > 0|
    end

    test "leaves the statement as it is without verdicts, for a type with verdict operations" do
      assert recheck(ReadersModule18, @recheck_mapping, false) == %{
               params: [:ids, :users, {:value, true}],
               sql:
                 recheck_sql(
                   ReadersModule18,
                   "FALSE",
                   ~s|("reviewed" = $3) IS TRUE|,
                   listed_readers_sql(~s|SELECT "steward_id"|, ~s|"steward_id" = "$c"."$reader"|)
                 )
             }
    end

    # The read verdict is true for every reader, so the statement reads nothing more for it.
    test "leaves the statement as it is for the read verdict, naming its key" do
      compiled = recheck(ReadersModule18, @recheck_mapping, false, true)

      assert Map.delete(compiled, :verdicts) == recheck(ReadersModule18, @recheck_mapping, false)

      assert compiled.verdicts == %{
               operations: [],
               read: [Policy.verdict_key(ReadersModule18, :read)]
             }
    end

    test "answers an operation whose rules name nobody once per row, reading no users" do
      space = "test_fixtures_policy_module26"

      none_sql =
        ~s|(NOT EXISTS (SELECT 1 FROM "hologram_data"."test_fixtures_policy_module27" AS "$q1" | <>
          ~s|WHERE "$q1"."space_id" = "#{space}"."id" AND "flagged" = $2)) IS TRUE|

      assert recheck(PolicyModule26, @recheck_mapping, false, true) == %{
               params: [:ids, {:value, true}],
               sql:
                 verdict_recheck_sql(PolicyModule26, %{
                   anonymous: "FALSE",
                   everyone: "TRUE",
                   readers: "'{}'::uuid[]",
                   verdict_anonymous: ["FALSE"],
                   verdict_everyone: [none_sql],
                   verdict_users: ["'{}'::uuid[]"]
                 }),
               verdicts: %{operations: [Policy.verdict_key(PolicyModule26, :delete)], read: []}
             }
    end

    defp cards_table, do: ~s|"hologram_data"."test_fixtures_policy_readers_module16"|

    # The open cards of the row the given table names, read through the derived set's bound slot.
    defp open_cards_sql(owner_table, owner_column, slot) do
      ~s|"$q1"."id" IN (SELECT "$s2"."id" FROM #{cards_table()} AS "$s2" | <>
        ~s|WHERE "$s2"."#{owner_column}" = "#{owner_table}"."id" AND "done" = $#{slot})|
    end

    # The close rule's any is bounded by the open cards' authors, and only the readers among them
    # are tested.
    test "tests the readers an operation's anchors name when its rules are listed" do
      board = "test_fixtures_policy_readers_module15"

      candidates_sql =
        ~s|SELECT "$cq1"."$reader" FROM #{cards_table()} AS "$q1" | <>
          ~s|CROSS JOIN LATERAL (SELECT "author_id") AS "$cq1"("$reader") | <>
          ~s|WHERE #{open_cards_sql(board, "board_id", 8)}|

      close_users_sql =
        ~s|CASE WHEN "$e"."$verdict_everyone"[2] THEN '{}'::uuid[] | <>
          ~s|ELSE ARRAY(SELECT DISTINCT "$c"."$reader" FROM (#{candidates_sql}) AS "$c"("$reader") | <>
          ~s|WHERE CASE WHEN "$e"."$everyone" | <>
          ~s|THEN ("$c"."$reader" IN (SELECT "$u"."$user" FROM unnest($2::uuid[]) AS "$u"("$user"))) IS TRUE | <>
          ~s|ELSE "$c"."$reader" = ANY("$r"."$readers") END | <>
          ~s|AND EXISTS (SELECT 1 FROM #{cards_table()} AS "$q1" | <>
          ~s|WHERE #{open_cards_sql(board, "board_id", 7)} AND "author_id" = "$c"."$reader")) END | <>
          ~s|AS "$verdict_users_2"|

      assert %{params: params, sql: sql, verdicts: verdicts} =
               recheck(ReadersModule15, @recheck_mapping, false, true)

      # The users are read for the verdicts alone - the board's read rule names nobody.
      assert [:ids, :users | _values] = params
      assert sql =~ close_users_sql
      assert Enum.at(verdicts.operations, 1) == Policy.verdict_key(ReadersModule15, :close)
    end

    # Each unlisted rule may hold for any reader, so every reader is tested, and an anonymous one is
    # answered by the rules folded for nobody.
    test "tests every reader when an operation's rule is unlisted, folding its rules for nobody" do
      holder = "test_fixtures_policy_readers_module17"

      share_sql = fn slot, condition_sql ->
        ~s|(EXISTS (SELECT 1 FROM #{cards_table()} AS "$q1" | <>
          ~s|WHERE #{open_cards_sql(holder, "holder_id", slot)} AND #{condition_sql})) IS TRUE|
      end

      close_users_sql =
        ~s|CASE WHEN "$e"."$verdict_everyone"[2] THEN '{}'::uuid[] | <>
          ~s|ELSE ARRAY(SELECT DISTINCT "$c"."$reader" | <>
          ~s|FROM (SELECT "$u"."$user" FROM unnest(CASE WHEN "$e"."$everyone" THEN $2::uuid[] | <>
          ~s|ELSE "$r"."$readers" END) AS "$u"("$user")) AS "$c"("$reader") | <>
          ~s|WHERE EXISTS (SELECT 1 FROM #{cards_table()} AS "$q1" | <>
          ~s|WHERE #{open_cards_sql(holder, "holder_id", 9)} | <>
          ~s|AND ("author_id" != "$c"."$reader" OR "author_id" IS NULL))) END AS "$verdict_users_2"|

      assert %{sql: sql, verdicts: verdicts} =
               recheck(ReadersModule17, @recheck_mapping, true, true)

      assert sql =~
               ~s|ARRAY[FALSE, FALSE, FALSE, FALSE, #{share_sql.(3, ~s|"done" = $4|)}, FALSE, | <>
                 ~s|#{share_sql.(5, ~s|"done" = $6|)}] AS "$verdict_anonymous"|

      assert sql =~
               ~s|ARRAY[#{Enum.join(List.duplicate("FALSE", 7), ", ")}] AS "$verdict_everyone"|

      assert sql =~ close_users_sql

      operations = [:claim, :close, :lock, :move, :share, :update, {:update, :name}]

      assert verdicts == %{
               operations: Enum.map(operations, &Policy.verdict_key(ReadersModule17, &1)),
               read: []
             }
    end

    defmodule SharedFieldBoard do
      use Hologram.Entity

      attribute :name, :string
      attribute :title, :string

      relationship :cards, [Hologram.Test.Fixtures.Policy.Readers.Module16]

      allow :read
      allow :update, except: [:name], when: none(cards)
    end

    # The title and the cards are covered by the one line, so their verdicts share a key, which the
    # statement answers once.
    test "answers the fields of an update the same lines cover once" do
      mapping =
        Mapper.derive!(
          [
            Module14,
            ReadersModule15,
            ReadersModule16,
            ReadersModule17,
            RoleGrant,
            SharedFieldBoard
          ],
          [Role.Module1, Role.Module2]
        )

      operations =
        for {_key, {:update, _field} = operation} <-
              Policy.verdict_operations(SharedFieldBoard),
            do: operation

      assert length(operations) > 1

      assert %{verdicts: %{operations: [key], read: []}} =
               recheck(SharedFieldBoard, mapping, false, true)

      assert key == Policy.verdict_key(SharedFieldBoard, {:update, :title})
    end

    test "answers no verdict for a type the server sends none on" do
      compiled = recheck(ReadersModule2, @recheck_mapping, false, true)

      assert Map.delete(compiled, :verdicts) == recheck(ReadersModule2, @recheck_mapping, false)
      assert compiled.verdicts == %{operations: [], read: []}
    end
  end

  describe "search_pattern/3" do
    test "folds the term of a loose search" do
      assert search_pattern("José", :prefix, :loose) == "jose%"
    end

    test "keeps the term of an exact search" do
      assert search_pattern("José", :infix, :exact) == "%José%"
    end

    test "escapes a backslash, % and _" do
      assert search_pattern("a\\b%c_d", :prefix, :exact) == "a\\\\b\\%c\\_d%"
    end
  end
end
