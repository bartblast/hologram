defmodule Hologram.Policy.ReadersTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Policy.Readers

  alias Hologram.Auth.RoleGrant
  alias Hologram.Policy
  alias Hologram.Test.Fixtures.Entity.Module14, as: EntityModule14
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module17, as: PolicyModule17
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2
  alias Hologram.Test.Fixtures.Policy.Module3, as: PolicyModule3
  alias Hologram.Test.Fixtures.Policy.Module5, as: PolicyModule5
  alias Hologram.Test.Fixtures.Policy.Module6, as: PolicyModule6
  alias Hologram.Test.Fixtures.Policy.Module8, as: PolicyModule8
  alias Hologram.Test.Fixtures.Policy.Readers.Module1
  alias Hologram.Test.Fixtures.Policy.Readers.Module11
  alias Hologram.Test.Fixtures.Policy.Readers.Module12
  alias Hologram.Test.Fixtures.Policy.Readers.Module15
  alias Hologram.Test.Fixtures.Policy.Readers.Module17
  alias Hologram.Test.Fixtures.Policy.Readers.Module18
  alias Hologram.Test.Fixtures.Policy.Readers.Module19
  alias Hologram.Test.Fixtures.Policy.Readers.Module2
  alias Hologram.Test.Fixtures.Policy.Readers.Module3
  alias Hologram.Test.Fixtures.Policy.Readers.Module4
  alias Hologram.Test.Fixtures.Policy.Readers.Module5
  alias Hologram.Test.Fixtures.Policy.Readers.Module6
  alias Hologram.Test.Fixtures.Policy.Readers.Module8
  alias Hologram.Test.Fixtures.Role

  defp rule(predicates, to \\ nil, via \\ nil) do
    %{predicates: predicates, to: to, via: via}
  end

  describe "classify/2" do
    test "an unconditional rule is independent" do
      assert classify(PolicyModule3) == [{:independent, rule([])}]
    end

    test "a rule naming nobody is independent" do
      [public, _grants] = classify(PolicyModule1)

      assert public == {:independent, rule([{:public, :==, true}])}
    end

    test "an equality on the acting user lists the readers by the name it compares" do
      assert classify(EntityModule14) == [
               {:listed, rule([{:id, :==, {:actor}}]), {:actor_equal, :id}}
             ]
    end

    test "an any whose condition compares the acting user lists the readers by its set" do
      predicates = [any: {[:members], [{:user_id, :==, {:actor}}]}]

      assert classify(Module1) == [
               {:listed, rule(predicates), {:any, [:members], {:actor_equal, :user_id}}}
             ]
    end

    test "an any over a path lists the readers by the set the path reaches" do
      predicates = [any: {[:project, :members], [{:user_id, :==, {:actor}}]}]

      assert classify(Module3) == [
               {:listed, rule(predicates), {:any, [:project, :members], {:actor_equal, :user_id}}}
             ]
    end

    test "grant references list the readers by their holders" do
      references = [{:own, [:viewer]}, {:type, PolicyModule2, [:admin]}]

      [_public, grants] = classify(PolicyModule1)

      assert grants == {:listed, rule([], references), {:grants, references}}
    end

    test "a top-level disjunction splits into one rule per alternative" do
      assert classify(PolicyModule6) == [
               {:listed, rule([{:author_id, :==, {:actor}}]), {:actor_equal, :author_id}},
               {:independent, rule([{:shared, :==, true}])}
             ]
    end

    test "a disjunction next to other clauses keeps them in every alternative" do
      member_any = {:any, {[:members], [{:user_id, :==, {:actor}}]}}

      assert classify(PolicyModule17) == [
               {:independent, rule([{:public, :==, true}])},
               {:listed, rule([member_any]), {:any, [:members], {:actor_equal, :user_id}}}
             ]
    end

    test "several top-level disjunctions split into every combination of their alternatives" do
      [_nested, _alternatives, _flattened, _outer | split] = classify(Module8)

      owner = {:owner_id, :==, {:actor}}

      assert Enum.take(split, 4) == [
               {:independent, rule([{:open, :==, true}, {:archived, :==, false}])},
               {:listed, rule([{:open, :==, true}, owner]), {:actor_equal, :owner_id}},
               {:listed, rule([owner, {:archived, :==, false}]), {:actor_equal, :owner_id}},
               {:listed, rule([owner]), {:actor_equal, :owner_id}}
             ]
    end

    test "an equality on a path lists the readers by the value the path reaches" do
      classes = classify(Module8)

      assert Enum.at(classes, 8) ==
               {:listed, rule([{[:sponsor, :id], :==, {:actor}}]),
                {:actor_equal, [:sponsor, :id]}}
    end

    test "an any over a derived set lists the readers by the rows the set holds" do
      classes = classify(Module8)
      {:listed, _rule, anchor} = List.last(classes)

      assert anchor ==
               {:any, [:lists], {:any, [:open_cards], {:actor_equal, :watcher_id}}}
    end

    test "a nested any lists the readers by the innermost set" do
      [{:listed, _rule, anchor} | _rest] = classify(Module8)

      assert anchor == {:any, [:lists], {:any, [:cards], {:actor_equal, :assignee_id}}}
    end

    test "a disjunction inside an any whose every alternative lists readers lists their union" do
      [_nested, {:listed, _rule, anchor} | _rest] = classify(Module8)

      assert anchor ==
               {:any, [:lists], {:or, [{:actor_equal, :lead_id}, {:actor_equal, :deputy_id}]}}
    end

    test "an any over a flattened chain lists the readers by the rows the chain reaches" do
      [_nested, _alternatives, {:listed, _rule, anchor} | _rest] = classify(Module8)

      assert anchor == {:any, [:lists, :cards], {:actor_equal, :reviewer_id}}
    end

    test "an equality on a name of the row outside a quantifier lists the readers by that name" do
      [_nested, _alternatives, _flattened, {:listed, _rule, anchor} | _rest] = classify(Module8)

      assert anchor == {:any, [:lists], {:actor_equal, {:outer, 1, :owner_id}}}
    end

    test "a disjunction inside an any with an alternative naming nobody is unlisted" do
      predicates = [
        any: {[:lists], [or: [[{:lead_id, :==, {:actor}}], [{:open, :==, true}]]]}
      ]

      [any | _rest] = classify(Module12)

      assert any == {:unlisted, rule(predicates)}
    end

    test "an any naming the acting user only in an inequality is unlisted" do
      [_alternatives, any | _rest] = classify(Module12)

      assert any == {:unlisted, rule(any: {[:lists], [{:lead_id, :!=, {:actor}}]})}
    end

    test "the acting user named only inside an all is unlisted" do
      [_alternatives, _inequality, all | _rest] = classify(Module12)

      assert all == {:unlisted, rule(all: {[:lists], [{:lead_id, :==, {:actor}}]})}
    end

    test "a disjunction inside an alternative is distributed too" do
      classes = classify(Module12)

      assert Enum.slice(classes, 3, 3) == [
               {:independent, rule([{:open, :==, true}])},
               {:listed, rule([{:archived, :==, false}, {:owner_id, :==, {:actor}}]),
                {:actor_equal, :owner_id}},
               {:independent, rule([{:archived, :==, false}, {:open, :==, false}])}
             ]
    end

    test "a split rule keeps its grant references, and a predicate bounds it before they do" do
      classes = classify(Module12)

      assert Enum.slice(classes, 6, 2) == [
               {:listed, rule([{:owner_id, :==, {:actor}}], own: [:viewer]),
                {:actor_equal, :owner_id}},
               {:listed, rule([{:open, :==, true}], own: [:viewer]), {:grants, [own: [:viewer]]}}
             ]
    end

    test "an inequality on the acting user is unlisted" do
      assert classify(Module5) == [{:unlisted, rule([{:owner_id, :!=, {:actor}}])}]
    end

    test "the acting user named only inside a none is unlisted" do
      predicates = [none: {[:blocks], [{:user_id, :==, {:actor}}]}]

      assert classify(Module6) == [{:unlisted, rule(predicates)}]
    end

    test "a delegation to listed rules lists the readers by the delegated anchors" do
      member_rule = rule(any: {[:members], [{:user_id, :==, {:actor}}]})
      member_anchor = {:any, [:members], {:actor_equal, :user_id}}

      assert classify(Module4) == [
               {:listed, rule([], nil, {:read, [:project], [member_rule]}),
                {:via, :read, [:project], [{member_rule, member_anchor}]}}
             ]
    end

    test "a delegation splits by the classes of the delegated rules" do
      public_rule = rule([{:public, :==, true}])
      references = [{:own, [:viewer]}, {:type, PolicyModule2, [:admin]}]
      grants_rule = rule([], references)

      assert classify(PolicyModule5) == [
               {:independent, rule([], nil, {:read, [:parent], [public_rule]})},
               {:listed, rule([], nil, {:read, [:parent], [grants_rule]}),
                {:via, :read, [:parent], [{grants_rule, {:grants, references}}]}}
             ]
    end

    test "a delegation to unlisted rules is unlisted" do
      unlisted_rule = rule([{:owner_id, :!=, {:actor}}])

      assert classify(Module11) == [
               {:unlisted, rule([], nil, {:read, [:owned], [unlisted_rule]})}
             ]
    end

    test "a delegation to an operation the related type declares no rule for is dropped" do
      classes = classify(Module12)

      refute Enum.any?(classes, fn class ->
               match?({:read, [:label], _rules}, elem(class, 1).via)
             end)
    end

    test "a delegation asks the related row the operation it names" do
      lead_rule = rule([{:lead_id, :==, {:actor}}])

      classes = classify(Module12)

      assert Enum.at(classes, 8) ==
               {:listed, rule([], nil, {:update, [:list], [lead_rule]}),
                {:via, :update, [:list], [{lead_rule, {:actor_equal, :lead_id}}]}}
    end

    test "a split delegation keeps the rule's own conditions, which bound it before it does" do
      owner = {:owner_id, :==, {:actor}}
      public_rule = rule([{:public, :==, true}])
      grants_rule = rule([], [{:own, [:viewer]}, {:type, PolicyModule2, [:admin]}])

      classes = classify(Module12)

      assert Enum.slice(classes, 9, 2) == [
               {:listed, rule([owner], nil, {:read, [:parent], [public_rule]}),
                {:actor_equal, :owner_id}},
               {:listed, rule([owner], nil, {:read, [:parent], [grants_rule]}),
                {:actor_equal, :owner_id}}
             ]
    end

    test "grant references bound a rule before its delegation does" do
      lead_rule = rule([{:lead_id, :==, {:actor}}])
      classes = classify(Module12)

      assert Enum.at(classes, 11) ==
               {:listed, rule([], [own: [:viewer]], {:update, [:list], [lead_rule]}),
                {:grants, [own: [:viewer]]}}
    end

    test "a delegation to a delegating type nests the delegated anchors" do
      references = [{:own, [:viewer]}, {:type, PolicyModule2, [:admin]}]
      grants_rule = rule([], references)
      public_rule = rule([{:public, :==, true}])
      delegated_grants_rule = rule([], nil, {:read, [:parent], [grants_rule]})

      delegated_grants_anchor =
        {:via, :read, [:parent], [{grants_rule, {:grants, references}}]}

      assert classify(PolicyModule8) == [
               {:independent,
                rule(
                  [],
                  nil,
                  {:read, [:parent], [rule([], nil, {:read, [:parent], [public_rule]})]}
                )},
               {:listed, rule([], nil, {:read, [:parent], [delegated_grants_rule]}),
                {:via, :read, [:parent], [{delegated_grants_rule, delegated_grants_anchor}]}}
             ]
    end

    test "classifies the grant store's framework-supplied rules" do
      [own | named] = classify(RoleGrant)

      assert own == {:listed, rule([{:user_id, :==, {:actor}}]), {:actor_equal, :user_id}}

      assert Enum.all?(named, &match?({:listed, _rule, {:grants, _references}}, &1))

      assert {:listed, _rule,
              {:grants,
               [
                 {:named, PolicyModule2, [:admin, :member]},
                 {:global, [Role.Module1, Role.Module2]}
               ]}} =
               Enum.find(named, fn {:listed, rule, _anchor} ->
                 rule.predicates == [{:entity_type, :==, PolicyModule2}]
               end)
    end

    test "classifies the rules of the given operation" do
      assert classify(Module2, :update) == []
    end
  end

  describe "classify_verdicts/1" do
    defp verdict_class(entity_type, clause) do
      entity_type
      |> classify_verdicts()
      |> Enum.find_value(fn {classified, _keys, class} -> if classified == clause, do: class end)
    end

    test "a clause naming nobody is independent" do
      assert verdict_class(Module15, {:none, {[:cards], []}}) == :independent
    end

    test "a server-only predicate naming nobody is independent" do
      assert verdict_class(Module18, {:reviewed, :==, true}) == :independent
    end

    test "an equality on the acting user answers no for the users it can't name" do
      assert verdict_class(Module18, {:steward_id, :==, {:actor}}) ==
               {:listed, {:actor_equal, :steward_id}, false}
    end

    test "an equality on a path answers no for the users the value it reaches can't name" do
      assert verdict_class(Module19, {[:report, :steward_id], :==, {:actor}}) ==
               {:listed, {:actor_equal, [:report, :steward_id]}, false}
    end

    test "an any bounded by its condition answers no for the users its set can't name" do
      clause = {:any, {[:open_cards], [{:author_id, :==, {:actor}}]}}

      assert verdict_class(Module15, clause) ==
               {:listed, {:any, [:open_cards], {:actor_equal, :author_id}}, false}
    end

    test "a none bounded by its condition answers yes for the users its set can't name" do
      clause = {:none, {[:cards], [{:author_id, :==, {:actor}}]}}

      assert verdict_class(Module15, clause) ==
               {:listed, {:any, [:cards], {:actor_equal, :author_id}}, true}
    end

    test "an inequality on the acting user is unlisted" do
      assert verdict_class(Module19, {[:report, :steward_id], :!=, {:actor}}) == :unlisted
    end

    test "an any over a derived set naming nobody is independent" do
      assert verdict_class(Module15, {:any, {[:open_cards], [{:done, :==, false}]}}) ==
               :independent
    end

    test "a none bounded by every alternative of its condition answers yes for the users none names" do
      clause =
        {:none,
         {[:cards], [or: [[{:author_id, :==, {:actor}}], [{:reviewer_id, :==, {:actor}}]]]}}

      assert verdict_class(Module15, clause) ==
               {:listed,
                {:any, [:cards],
                 {:or, [{:actor_equal, :author_id}, {:actor_equal, :reviewer_id}]}}, true}
    end

    test "an all of one inequality on the acting user answers yes for the users its set can't name" do
      clause = {:all, {[:cards], [{:author_id, :!=, {:actor}}]}}

      assert verdict_class(Module15, clause) ==
               {:listed, {:any, [:cards], {:actor_equal, :author_id}}, true}
    end

    test "any other all naming the acting user is unlisted" do
      assert verdict_class(Module17, {:all, {[:cards], [{:author_id, :==, {:actor}}]}}) ==
               :unlisted
    end

    test "an any with an alternative naming nobody is unlisted" do
      clause =
        {:any, {[:open_cards], [or: [[{:author_id, :==, {:actor}}], [{:done, :==, true}]]]}}

      assert verdict_class(Module17, clause) == :unlisted
    end

    test "an any whose condition bounds nobody is unlisted" do
      assert verdict_class(Module17, {:any, {[:open_cards], [{:author_id, :!=, {:actor}}]}}) ==
               :unlisted
    end

    test "a none whose condition bounds nobody is unlisted" do
      clause = {:none, {[:cards], [or: [[{:done, :==, true}], [{:author_id, :==, {:actor}}]]]}}

      assert verdict_class(Module17, clause) == :unlisted
    end

    test "a clause several operations share is one entry with every key" do
      clause = {:none, {[:cards], [{:author_id, :==, {:actor}}]}}

      assert {^clause, keys, _class} =
               Module15
               |> classify_verdicts()
               |> Enum.find(&(elem(&1, 0) == clause))

      assert keys == [
               Policy.verdict_key(Module15, :archive, clause),
               Policy.verdict_key(Module15, :update, clause),
               Policy.verdict_key(Module15, {:update, :name}, clause)
             ]
    end

    test "lists the clauses in the order of their first keys" do
      operations =
        Module15
        |> classify_verdicts()
        |> Enum.map(fn {_clause, [key | _rest], _class} ->
          [operation | _digest] = String.split(key, ":")
          operation
        end)

      assert operations == ["archive", "close", "delete", "hide", "pin", "review"]
    end

    test "a type with no deciding clause has none" do
      assert classify_verdicts(Module1) == []
    end
  end
end
