defmodule Hologram.Policy.EvaluatorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Policy.Evaluator

  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module17
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module22
  alias Hologram.Test.Fixtures.Entity.Module24
  alias Hologram.Test.Fixtures.Entity.Module41
  alias Hologram.Test.Fixtures.Entity.Module42
  alias Hologram.Test.Fixtures.Policy.Module1
  alias Hologram.Test.Fixtures.Policy.Module12

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

    test "answers a per-role operation keyed by a tuple" do
      entity = %Module1{}
      policy = %{{:grant_role, :viewer} => [rule(to: [{:own, [:editor]}])]}

      assert grants?(policy, {:grant_role, :viewer}, entity, "user_id_1", &grant/3)
      refute grants?(policy, {:grant_role, :editor}, entity, "user_id_1", &grant/3)
    end

    # Asked through the policy, so the operation the rule is keyed by is at hand and must not be the
    # one the checker hears.
    test "asks the checker the operation a delegation names" do
      checker = fn requirement, _entity, _actor_user_id ->
        requirement == {:via, :update, [:parent]}
      end

      policy = %{create: [rule(via: {:update, [:parent]})]}

      assert grants?(policy, :create, %Module1{}, "user_id_1", checker)
    end
  end

  describe "rule_matches?/4" do
    # The row the note relationship leads to, as the checker reads it for a path.
    defp note_checker(note) do
      fn {:related, [:note]}, _entity, _actor_user_id -> note end
    end

    test "computes a derived field from the row a path in its definition reads" do
      rule = rule(predicates: [{:note_hidden, :==, true}])
      entity = %Module42{note_id: "n1"}

      assert rule_matches?(rule, entity, nil, note_checker(%Module41{public: false}))
      refute rule_matches?(rule, entity, nil, note_checker(%Module41{public: true}))
      refute rule_matches?(rule, %Module42{}, nil, note_checker(nil))
    end

    test "computes a derived field reading another, nil where a string it joins is" do
      rule = rule(predicates: [{:shout, :==, "draft!!"}])
      missing_rule = rule(predicates: [{:shout, :==, nil}])

      assert rule_matches?(rule, %Module42{title: "draft"}, nil, &deny/3)
      assert rule_matches?(missing_rule, %Module42{title: nil}, nil, &deny/3)
    end

    test "compares a derived enum by its declared order" do
      rule = rule(predicates: [{:rank, :<, :low}])

      assert rule_matches?(rule, %Module42{score: 9}, nil, &deny/3)
      refute rule_matches?(rule, %Module42{score: 1}, nil, &deny/3)
    end

    test "takes a derived if's else branch when its condition reads nil" do
      rule = rule(predicates: [{:rank, :==, :low}])

      assert rule_matches?(rule, %Module42{score: nil}, nil, &deny/3)
    end

    test "computes a derived field on the row a path leads to" do
      rule = rule(predicates: [{[:origin, :shout], :==, "draft!!"}])
      checker = fn {:related, [:origin]}, _entity, _actor_user_id -> %Module42{title: "draft"} end
      missing_checker = fn {:related, [:origin]}, _entity, _actor_user_id -> nil end

      assert rule_matches?(rule, %Module42{}, nil, checker)
      refute rule_matches?(rule, %Module42{}, nil, missing_checker)
    end

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

    test "evaluates either alternative of a disjunction" do
      rule = rule(predicates: [{:or, [[{:public, :==, true}], [{:priority, :>=, 3}]]}])

      assert rule_matches?(rule, %Module1{public: true, priority: 1}, nil, &deny/3)
      assert rule_matches?(rule, %Module1{public: false, priority: 3}, nil, &deny/3)
      refute rule_matches?(rule, %Module1{public: false, priority: 1}, nil, &deny/3)
    end

    test "evaluates a nested disjunction" do
      rule =
        rule(
          predicates: [
            {:or,
             [
               [{:public, :==, true}, {:or, [[{:priority, :==, 1}], [{:priority, :==, 2}]]}],
               [{:priority, :>=, 5}]
             ]}
          ]
        )

      assert rule_matches?(rule, %Module1{public: true, priority: 2}, nil, &deny/3)
      assert rule_matches?(rule, %Module1{public: false, priority: 5}, nil, &deny/3)
      refute rule_matches?(rule, %Module1{public: true, priority: 3}, nil, &deny/3)
    end

    # Two times compared as plain maps read the microseconds before the minutes.
    test "orders two times by the time of day they name" do
      entity = %Module22{opens_at: ~T[10:05:00.900000]}

      assert rule_matches?(
               rule(predicates: [{:opens_at, :<, ~T[10:30:00.100000]}]),
               entity,
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:opens_at, :>, ~T[10:30:00.100000]}]),
               entity,
               nil,
               &deny/3
             )
    end

    test "equals two times naming the same time of day at different precisions" do
      assert rule_matches?(
               rule(predicates: [{:opens_at, :==, ~T[10:00:00.000000]}]),
               %Module22{opens_at: ~T[10:00:00]},
               nil,
               &deny/3
             )
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

    # A missing value is unequal to every value but another missing one, the acting user's id
    # included - a rule on an unset reference never grants a signed-in user.
    test "never equates a missing reference with the acting user" do
      entity = %Module1{author_id: nil}

      refute rule_matches?(
               rule(predicates: [{:author_id, :==, {:actor}}]),
               entity,
               "user_id_1",
               &deny/3
             )

      assert rule_matches?(
               rule(predicates: [{:author_id, :!=, {:actor}}]),
               entity,
               "user_id_1",
               &deny/3
             )
    end

    test "never equates a missing string with a literal" do
      entity = %Module2{c: nil}

      refute rule_matches?(rule(predicates: [{:c, :==, "draft"}]), entity, nil, &deny/3)
      assert rule_matches?(rule(predicates: [{:c, :!=, "draft"}]), entity, nil, &deny/3)
      refute rule_matches?(rule(predicates: [{:c, :in, ["draft"]}]), entity, nil, &deny/3)
    end

    test "never equates a missing number with zero" do
      entity = %Module1{priority: nil}

      refute rule_matches?(rule(predicates: [{:priority, :==, 0}]), entity, nil, &deny/3)
      assert rule_matches?(rule(predicates: [{:priority, :!=, 0}]), entity, nil, &deny/3)
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

    # A rule and the filter mirroring it have to admit the same rows, so a string compares here the
    # way a query compares it - by its derived key, then by the value behind it.
    test "compares a string attribute by its sort key" do
      assert rule_matches?(
               rule(predicates: [{:username, :>=, "m"}]),
               %Module10{count: 1, username: "Mango"},
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:username, :>=, "m"}]),
               %Module10{count: 1, username: "Łódź"},
               nil,
               &deny/3
             )
    end

    test "settles a string bound that shares a key by the value itself" do
      assert rule_matches?(
               rule(predicates: [{:username, :>, "Zebra"}]),
               %Module10{count: 1, username: "zebra"},
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:username, :>, "Zebra"}]),
               %Module10{count: 1, username: "Zebra"},
               nil,
               &deny/3
             )
    end

    test "compares a character above U+FFFF after one from U+E000 to U+FFFF" do
      assert rule_matches?(
               rule(predicates: [{:username, :>, "\uFFFD"}]),
               %Module10{count: 1, username: "😀"},
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:username, :>, "\uFFFD"}]),
               %Module10{count: 1, username: "\uFFFD"},
               nil,
               &deny/3
             )
    end

    # A rule and the filter mirroring it have to admit the same rows, so a search matches here the
    # way a query matches it.
    test "matches a loose search ignoring case and accents" do
      assert rule_matches?(
               rule(predicates: [{:username, :starts_with, "jose"}]),
               %Module10{count: 1, username: "José"},
               nil,
               &deny/3
             )

      assert rule_matches?(
               rule(predicates: [{:username, :contains, "STRASSE"}]),
               %Module10{count: 1, username: "Straße"},
               nil,
               &deny/3
             )
    end

    test "matches an exact search byte for byte" do
      assert rule_matches?(
               rule(predicates: [{:username, :starts_with_exact, "Jo"}]),
               %Module10{count: 1, username: "José"},
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:username, :contains_exact, "jose"}]),
               %Module10{count: 1, username: "José"},
               nil,
               &deny/3
             )
    end

    test "matches a search for another attribute's value" do
      assert rule_matches?(
               rule(predicates: [{:bio, :contains, {:attribute, :username}}]),
               %Module10{bio: "Hi, I'm ADA", count: 1, username: "ada"},
               nil,
               &deny/3
             )
    end

    test "never matches a search for another attribute when either is missing" do
      refute rule_matches?(
               rule(predicates: [{:bio, :contains, {:attribute, :username}}]),
               %Module10{bio: "Hi, I'm Ada", count: 1},
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:bio, :starts_with_exact, {:attribute, :username}}]),
               %Module10{count: 1, username: "ada"},
               nil,
               &deny/3
             )
    end

    test "passes over a missing value in a search" do
      refute rule_matches?(
               rule(predicates: [{:username, :contains, ""}]),
               %Module10{count: 1, username: nil},
               nil,
               &deny/3
             )
    end

    # The key folds case and diacritics, and `==` must not: what a bound reaches and what a value
    # equals are two different questions.
    test "keeps string equality exact" do
      assert rule_matches?(
               rule(predicates: [{:username, :==, "Zebra"}]),
               %Module10{count: 1, username: "Zebra"},
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:username, :==, "Zebra"}]),
               %Module10{count: 1, username: "zebra"},
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

    # Unequal values as well as equal ones: an operand never read would compare as a tie.
    test "compares two attributes of the row" do
      entity = %Module10{count: 3, priority: 3}
      below = %Module10{count: 3, priority: 5}

      assert rule_matches?(
               rule(predicates: [{:count, :<, {:attribute, :priority}}]),
               below,
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:count, :>, {:attribute, :priority}}]),
               below,
               nil,
               &deny/3
             )

      assert rule_matches?(
               rule(predicates: [{:count, :>=, {:attribute, :priority}}]),
               entity,
               nil,
               &deny/3
             )

      assert rule_matches?(
               rule(predicates: [{:count, :<=, {:attribute, :priority}}]),
               entity,
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:count, :>, {:attribute, :priority}}]),
               entity,
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:count, :<, {:attribute, :priority}}]),
               entity,
               nil,
               &deny/3
             )
    end

    test "evaluates an attribute equality with nil as a regular value" do
      assert rule_matches?(
               rule(predicates: [{:starts_on, :==, {:attribute, :ends_on}}]),
               %Module24{},
               nil,
               &deny/3
             )

      assert rule_matches?(
               rule(predicates: [{:starts_on, :!=, {:attribute, :ends_on}}]),
               %Module24{starts_on: ~D[2026-03-01]},
               nil,
               &deny/3
             )
    end

    # A number sorts before nil as a term, and the browser reads a missing value as 0, so each tier
    # would let one pair of these through if it compared the missing value at all.
    test "never matches an ordering comparison between attributes when either is missing" do
      refute rule_matches?(
               rule(predicates: [{:count, :<=, {:attribute, :priority}}]),
               %Module10{count: 3},
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:priority, :>=, {:attribute, :count}}]),
               %Module10{count: 3},
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:count, :>=, {:attribute, :priority}}]),
               %Module10{count: 3},
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:priority, :<=, {:attribute, :count}}]),
               %Module10{count: 3},
               nil,
               &deny/3
             )
    end

    # Zebra sorts after apple by its key and before it by its bytes. Mango and mango share a key,
    # so the values settle it.
    test "compares two string attributes by their sort keys" do
      assert rule_matches?(
               rule(predicates: [{:username, :>, {:attribute, :bio}}]),
               %Module10{bio: "apple", count: 1, username: "Zebra"},
               nil,
               &deny/3
             )

      assert rule_matches?(
               rule(predicates: [{:username, :<, {:attribute, :bio}}]),
               %Module10{bio: "mango", count: 1, username: "Mango"},
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:username, :>, {:attribute, :bio}}]),
               %Module10{bio: "mango", count: 1, username: "Mango"},
               nil,
               &deny/3
             )
    end

    # :high is after :medium in the declared list and before it as an atom.
    test "compares two enum attributes by their declared position" do
      assert rule_matches?(
               rule(predicates: [{:level, :>, {:attribute, :priority}}]),
               %Module24{level: :high, priority: :medium},
               nil,
               &deny/3
             )
    end

    test "compares an integer attribute with a float attribute" do
      entity = %Module10{count: 2, rating: 2.0}

      assert rule_matches?(
               rule(predicates: [{:count, :<, {:attribute, :rating}}]),
               %Module10{count: 2, rating: 2.5},
               nil,
               &deny/3
             )

      assert rule_matches?(
               rule(predicates: [{:count, :==, {:attribute, :rating}}]),
               entity,
               nil,
               &deny/3
             )

      assert rule_matches?(
               rule(predicates: [{:count, :<=, {:attribute, :rating}}]),
               entity,
               nil,
               &deny/3
             )

      refute rule_matches?(
               rule(predicates: [{:count, :<, {:attribute, :rating}}]),
               entity,
               nil,
               &deny/3
             )
    end

    test "reads a path's attribute off the row its relationships lead to" do
      rule = rule(predicates: [{[:parent, :parent, :public], :==, true}])

      public_checker = fn {:related, [:parent, :parent]}, _entity, _actor_user_id ->
        %Module1{public: true}
      end

      private_checker = fn {:related, [:parent, :parent]}, _entity, _actor_user_id ->
        %Module1{public: false}
      end

      assert rule_matches?(rule, %Module12{}, nil, public_checker)
      refute rule_matches?(rule, %Module12{}, nil, private_checker)
    end

    # The relationships lead nowhere, so the path reads nil, which compares the way a missing
    # attribute does.
    test "reads a path that ends nowhere as nil" do
      checker = fn {:related, [:parent, :parent]}, _entity, _actor_user_id -> nil end

      refute rule_matches?(
               rule(predicates: [{[:parent, :parent, :public], :==, false}]),
               %Module12{},
               nil,
               checker
             )

      assert rule_matches?(
               rule(predicates: [{[:parent, :parent, :public], :!=, true}]),
               %Module12{},
               nil,
               checker
             )

      assert rule_matches?(
               rule(predicates: [{[:parent, :parent, :public], :==, nil}]),
               %Module12{},
               nil,
               checker
             )

      refute rule_matches?(
               rule(predicates: [{[:parent, :parent, :priority], :>=, 3}]),
               %Module12{},
               nil,
               checker
             )
    end

    # High sorts before medium as an atom and after it in the declared list.
    test "compares a path's enum by the declared position of the attribute it ends at" do
      rule = rule(predicates: [{[:link, :priority], :>, :medium}])

      high_checker = fn {:related, [:link]}, _entity, _actor_user_id ->
        %Module17{priority: :high}
      end

      low_checker = fn {:related, [:link]}, _entity, _actor_user_id ->
        %Module17{priority: :low}
      end

      assert rule_matches?(rule, %Module12{}, nil, high_checker)
      refute rule_matches?(rule, %Module12{}, nil, low_checker)
    end

    test "compares a path's string by its sort key" do
      rule = rule(predicates: [{[:link, :label], :>=, "m"}])

      mango_checker = fn {:related, [:link]}, _entity, _actor_user_id ->
        %Module17{label: "Mango"}
      end

      lodz_checker = fn {:related, [:link]}, _entity, _actor_user_id ->
        %Module17{label: "Łódź"}
      end

      assert rule_matches?(rule, %Module12{}, nil, mango_checker)
      refute rule_matches?(rule, %Module12{}, nil, lodz_checker)
    end

    test "compares an attribute with a path operand" do
      rule = rule(predicates: [{:level, :<=, {:attribute, [:parent, :parent, :priority]}}])

      checker = fn {:related, [:parent, :parent]}, _entity, _actor_user_id ->
        %Module1{priority: 3}
      end

      assert rule_matches?(rule, %Module12{level: 3}, nil, checker)
      refute rule_matches?(rule, %Module12{level: 4}, nil, checker)
    end

    test "substitutes the actor in predicate values" do
      entity = %Module1{author_id: "user_id_1"}
      rule = rule(predicates: [{:author_id, :==, {:actor}}])

      assert rule_matches?(rule, entity, "user_id_1", &deny/3)
      refute rule_matches?(rule, entity, "user_id_2", &deny/3)
    end

    test "denies a rule referencing the actor to an anonymous session" do
      rule = rule(predicates: [{:author_id, :==, {:actor}}])

      refute rule_matches?(rule, %Module1{author_id: nil}, nil, &deny/3)
    end

    test "denies a rule with grant references to an anonymous session" do
      rule = rule(to: [{:own, [:owner]}])

      refute rule_matches?(rule, %Module1{}, nil, &grant/3)
    end

    # The actor of an anonymous session is nobody, never nil - nil would equal the missing author
    # and hand the visitor every authorless row through the first alternative.
    test "passes a visitor to the alternative that names nobody" do
      rule = rule(predicates: [{:or, [[{:author_id, :==, {:actor}}], [{:public, :==, true}]]}])

      assert rule_matches?(rule, %Module1{author_id: nil, public: true}, nil, &deny/3)
      refute rule_matches?(rule, %Module1{author_id: nil, public: false}, nil, &deny/3)
    end

    test "denies a visitor every alternative naming them" do
      rule =
        rule(predicates: [{:or, [[{:author_id, :==, {:actor}}], [{:author_id, :!=, {:actor}}]]}])

      refute rule_matches?(rule, %Module1{author_id: nil}, nil, &deny/3)
    end

    test "denies a visitor a conjunction naming them beside a disjunction" do
      rule =
        rule(
          predicates: [
            {:author_id, :!=, {:actor}},
            {:or, [[{:public, :==, true}], [{:priority, :>=, 3}]]}
          ]
        )

      entity = %Module1{author_id: nil, public: true}

      assert rule_matches?(rule, entity, "user_id_1", &deny/3)
      refute rule_matches?(rule, entity, nil, &deny/3)
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
      rule = rule(via: {:read, [:parent]})

      assert rule_matches?(rule, %Module1{}, "user_id_1", &grant/3)
      refute rule_matches?(rule, %Module1{}, "user_id_1", &deny/3)
    end

    test "asks the checker the chain a delegation follows" do
      checker = fn {:via, :read, [:parent, :parent]}, _entity, _actor_user_id -> true end

      assert rule_matches?(
               rule(via: {:read, [:parent, :parent]}),
               %Module1{},
               "user_id_1",
               checker
             )
    end

    test "evaluates a delegating rule for an anonymous session" do
      checker = fn {:via, :read, [:parent]}, _entity, actor_user_id -> is_nil(actor_user_id) end

      assert rule_matches?(rule(via: {:read, [:parent]}), %Module1{}, nil, checker)
    end
  end
end
