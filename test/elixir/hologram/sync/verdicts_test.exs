defmodule Hologram.Sync.VerdictsTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.Verdicts
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Entity
  alias Hologram.Policy
  alias Hologram.Test.Fixtures.Entity.Module2

  use_module_stub :query_cache

  # A task may be deleted while its board holds no card by the user - read through the task's
  # board, so a task with no board has an empty set, answered without reading the database: yes for
  # a user, and no for a visitor, since the rule asks about the actor.
  defmodule VerdictBoard do
    use Hologram.Entity

    relationship :cards, [__MODULE__.Card], inverse: board

    allow :read

    defmodule Card do
      use Hologram.Entity

      relationship :author, Hologram.Test.Fixtures.Entity.Module14, optional: true
      relationship :board, Hologram.Sync.VerdictsTest.VerdictBoard, optional: true

      allow :read
    end
  end

  defmodule VerdictTask do
    use Hologram.Entity

    relationship :board, VerdictBoard, optional: true

    allow :read
    allow :delete, when: none(card <- board.cards, card.author_id == user_id())
  end

  setup do
    stub_with(QueryCacheMock, QueryCacheStub)
    :persistent_term.put(QueryCacheStub.persistent_term_key(), %{permission_checking?: true})

    on_exit(fn -> :persistent_term.erase(QueryCacheStub.persistent_term_key()) end)
  end

  defp delete_key do
    Policy.verdict_key(
      VerdictTask,
      :delete,
      {:none, {[:board, :cards], [{:author_id, :==, {:actor}}]}}
    )
  end

  defp task, do: %{VerdictTask.new() | id: Entity.generate_id()}

  describe "remember/2" do
    test "records the verdicts a put carries, and forgets them for a put carrying none" do
      told = remember(%{}, [%{data: %{"$verdicts": %{"k" => true}}, id: "a", op: :put_entity}])

      assert told == %{"a" => %{"k" => true}}
      assert remember(told, [%{data: %{}, id: "a", op: :put_entity}]) == %{}
    end

    test "replaces the verdicts a patch carries and leaves them for a patch carrying none" do
      told = %{"a" => %{"k" => true}}

      assert remember(told, [%{data: %{"$verdicts": %{"k" => false}}, id: "a", op: :patch_entity}]) ==
               %{"a" => %{"k" => false}}

      assert remember(told, [%{data: %{c: "x"}, id: "a", op: :patch_entity}]) == told
    end

    test "forgets the verdicts of a row that left the client" do
      assert remember(%{"a" => %{"k" => true}}, [%{id: "a", op: :unsync_entity}]) == %{}
    end

    test "forgets the verdicts of a row put and then unsynced in the same deltas" do
      deltas = [
        %{data: %{"$verdicts": %{"k" => true}}, id: "a", op: :put_entity},
        %{id: "a", op: :unsync_entity}
      ]

      assert remember(%{}, deltas) == %{}
    end
  end

  describe "patches/2" do
    test "puts the stale verdicts of a patched row beside its changes" do
      row = task()

      assert patches([{row, %{c: "x"}}], [{row, %{"k" => false}}]) == [
               {row, %{c: "x"}, %{"k" => false}}
             ]
    end

    test "leaves no verdicts on a patched row whose verdicts did not move" do
      row = task()

      assert patches([{row, %{c: "x"}}], []) == [{row, %{c: "x"}, nil}]
    end

    test "adds a patch naming no value for a row whose verdicts alone moved, in id order after the others" do
      patched = %{task() | id: "b"}
      first = %{task() | id: "c"}
      last = %{task() | id: "d"}

      assert patches([{patched, %{c: "x"}}], [{last, %{"k" => true}}, {first, %{"k" => false}}]) ==
               [
                 {patched, %{c: "x"}, nil},
                 {first, %{}, %{"k" => false}},
                 {last, %{}, %{"k" => true}}
               ]
    end
  end

  describe "stale/5" do
    test "returns a row whose verdicts differ from what was told when the round touched what they read" do
      row = task()
      user_id = Entity.generate_id()
      changed_types = MapSet.new([VerdictBoard.Card])

      assert stale([row], %{}, user_id, changed_types) == [{row, %{delete_key() => true}}]
    end

    test "returns the rows in the order given" do
      first = task()
      last = task()
      changed_types = MapSet.new([VerdictBoard.Card])

      assert stale([last, first], %{}, Entity.generate_id(), changed_types) == [
               {last, %{delete_key() => true}},
               {first, %{delete_key() => true}}
             ]
    end

    test "returns a patched row when the round touched only the rule's own type" do
      row = task()
      changed_types = MapSet.new([VerdictTask])
      patched_ids = MapSet.new([row.id])

      assert stale([row], %{}, Entity.generate_id(), changed_types, patched_ids) == [
               {row, %{delete_key() => true}}
             ]
    end

    test "returns nothing for a row the round left alone when it touched only the rule's own type" do
      changed_types = MapSet.new([VerdictTask])

      assert stale([task()], %{}, Entity.generate_id(), changed_types, MapSet.new()) == []
    end

    test "returns nothing for a row whose verdicts are what was told" do
      row = task()
      told = %{row.id => %{delete_key() => true}}

      assert stale([row], told, Entity.generate_id(), MapSet.new([VerdictBoard.Card])) == []
    end

    test "returns nothing when the round touched nothing the verdicts read" do
      assert stale([task()], %{}, Entity.generate_id(), MapSet.new([Module2])) == []
    end

    test "returns every row whose verdicts differ when asked for all" do
      row = task()

      assert stale([row], %{row.id => %{delete_key() => true}}, nil, :all) == [
               {row, %{delete_key() => false}}
             ]
    end

    test "returns nothing for a row of a type with no deciding quantifier" do
      assert stale([Module2.new(a: true)], %{}, nil, :all) == []
    end
  end
end
