defmodule Hologram.Policy.EvaluatorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Policy.Evaluator

  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module17
  alias Hologram.Test.Fixtures.Policy.Module1

  defp deny(_requirement, _entity, _actor_user_id), do: false

  defp grant(_requirement, _entity, _actor_user_id), do: true

  defp rule(fields) do
    Enum.into(fields, %{predicates: [], to: nil, via: nil})
  end

  describe "grants?/5" do
    test "returns false for an operation with no rules" do
      entity = %Module1{public: true}

      refute grants?(%{}, :read, entity, nil, &deny/3)
    end

    test "returns true when any rule of the operation matches" do
      entity = %Module1{public: true, priority: 1}

      policy = %{
        read: [
          rule(predicates: [{:priority, :>=, 3}]),
          rule(predicates: [{:public, :==, true}])
        ]
      }

      assert grants?(policy, :read, entity, nil, &deny/3)
    end

    test "returns false when no rule of the operation matches" do
      entity = %Module1{public: false, priority: 1}

      policy = %{
        read: [
          rule(predicates: [{:priority, :>=, 3}]),
          rule(predicates: [{:public, :==, true}])
        ]
      }

      refute grants?(policy, :read, entity, nil, &deny/3)
    end

    test "returns false for an operation other than the rules' one" do
      entity = %Module1{public: true}
      policy = %{read: [rule(predicates: [{:public, :==, true}])]}

      refute grants?(policy, :delete, entity, nil, &deny/3)
    end
  end

  describe "rule_matches?/4" do
    test "requires every predicate of the rule to hold" do
      entity = %Module1{public: true, priority: 1}

      assert rule_matches?(
               rule(predicates: [{:public, :==, true}, {:priority, :==, 1}]),
               entity,
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:public, :==, true}, {:priority, :==, 3}]),
               entity,
               nil,
               &deny/3
             )
    end

    test "matches a rule without predicates" do
      assert rule_matches?(rule([]), %Module1{}, nil, &deny/3)
    end

    test "evaluates equality with nil as a regular value" do
      assert rule_matches?(rule(predicates: [{:priority, :==, nil}]), %Module1{}, nil, &deny/3)

      refute rule_matches?(
               rule(predicates: [{:priority, :==, nil}]),
               %Module1{priority: 1},
               nil,
               &deny/3
             )
    end

    test "evaluates inequality with nil as a regular value" do
      assert rule_matches?(rule(predicates: [{:priority, :!=, 1}]), %Module1{}, nil, &deny/3)

      refute rule_matches?(
               rule(predicates: [{:priority, :!=, 1}]),
               %Module1{priority: 1},
               nil,
               &deny/3
             )
    end

    test "evaluates membership with nil as a regular element" do
      assert rule_matches?(
               rule(predicates: [{:priority, :in, [nil, 3]}]),
               %Module1{},
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:priority, :in, [1, 3]}]),
               %Module1{},
               nil,
               &deny/3
             )
    end

    test "evaluates negated membership with nil as a regular element" do
      assert rule_matches?(
               rule(predicates: [{:priority, :not_in, [1, 3]}]),
               %Module1{},
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:priority, :not_in, [nil, 3]}]),
               %Module1{},
               nil,
               &deny/3
             )
    end

    test "evaluates ordering comparisons" do
      entity = %Module1{priority: 3}

      assert rule_matches?(rule(predicates: [{:priority, :>=, 3}]), entity, nil, &deny/3)
      assert rule_matches?(rule(predicates: [{:priority, :<=, 3}]), entity, nil, &deny/3)
      refute rule_matches?(rule(predicates: [{:priority, :>, 3}]), entity, nil, &deny/3)
      refute rule_matches?(rule(predicates: [{:priority, :<, 3}]), entity, nil, &deny/3)
    end

    test "never matches ordering comparisons against a missing value" do
      refute rule_matches?(rule(predicates: [{:priority, :>=, 3}]), %Module1{}, nil, &deny/3)
      refute rule_matches?(rule(predicates: [{:priority, :<=, 3}]), %Module1{}, nil, &deny/3)

      refute rule_matches?(
               rule(predicates: [{:priority, :>=, nil}]),
               %Module1{priority: 3},
               nil,
               &deny/3
             )
    end

    test "orders temporal values by their calendar semantics" do
      entity = %Module10{count: 1, held_at: ~U[2026-07-17 12:00:00Z], released_on: ~D[2026-07-17]}

      assert rule_matches?(
               rule(predicates: [{:held_at, :>, ~U[2026-01-01 00:00:00Z]}]),
               entity,
               nil,
               &deny/3
             )

      assert rule_matches?(
               rule(predicates: [{:released_on, :<, ~D[2027-01-01]}]),
               entity,
               nil,
               &deny/3
             )
    end

    # Declared order, not atom order: :high is the LAST declared value of [:low, :medium, :high]
    # while it is the FIRST alphabetically, so a term comparison would answer the other way.
    test "orders enum values by their declared position" do
      assert rule_matches?(
               rule(predicates: [{:priority, :>=, :medium}]),
               %Module17{priority: :high},
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:priority, :>=, :medium}]),
               %Module17{priority: :low},
               nil,
               &deny/3
             )
    end

    test "never matches an enum comparison against an unset value" do
      refute rule_matches?(
               rule(predicates: [{:priority, :>=, :low}]),
               %Module17{},
               nil,
               &deny/3
             )
    end

    test "substitutes the actor in predicate values" do
      entity = %Module1{author_id: "user_id_1"}
      rule = rule(predicates: [{:author_id, :==, {:actor}}])

      assert rule_matches?(rule, entity, "user_id_1", &deny/3)
      refute rule_matches?(rule, entity, "user_id_2", &deny/3)
    end

    test "skips a rule referencing the actor for an anonymous session" do
      rule = rule(predicates: [{:author_id, :==, {:actor}}])

      refute rule_matches?(rule, %Module1{author_id: nil}, nil, &deny/3)
    end

    test "skips a rule with grant references for an anonymous session" do
      rule = rule(to: [{:own, [:owner]}])

      refute rule_matches?(rule, %Module1{}, nil, &grant/3)
    end

    test "grants when the checker holds one of the rule's grant references" do
      checker = fn
        {:own, [:owner]}, _entity, _actor_user_id -> false
        {:type, _target_type, [:admin]}, _entity, _actor_user_id -> true
      end

      rule = rule(to: [{:own, [:owner]}, {:type, Module1, [:admin]}])

      assert rule_matches?(rule, %Module1{}, "user_id_1", checker)
      refute rule_matches?(rule, %Module1{}, "user_id_1", &deny/3)
    end

    test "requires the predicates to hold alongside the grant references" do
      rule = rule(predicates: [{:priority, :>=, 3}], to: [{:own, [:owner]}])

      assert rule_matches?(rule, %Module1{priority: 3}, "user_id_1", &grant/3)
      refute rule_matches?(rule, %Module1{priority: 1}, "user_id_1", &grant/3)
    end

    test "delegates to the checker for a via requirement" do
      rule = rule(via: :parent)

      assert rule_matches?(rule, %Module1{}, "user_id_1", &grant/3)
      refute rule_matches?(rule, %Module1{}, "user_id_1", &deny/3)
    end

    test "evaluates a delegating rule for an anonymous session" do
      checker = fn {:via, :parent}, _entity, actor_user_id -> is_nil(actor_user_id) end

      assert rule_matches?(rule(via: :parent), %Module1{}, nil, checker)
    end
  end
end
