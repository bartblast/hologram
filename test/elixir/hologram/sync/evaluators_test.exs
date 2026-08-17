defmodule Hologram.Sync.EvaluatorsTest do
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Sync.Evaluators
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.DB
  alias Hologram.Query
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.ResultStore
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Sync.VanishingEvaluator

  use_module_stub :query_cache

  setup :set_mox_global

  @window_id "w_7f3a"

  setup do
    setup_query_cache(QueryCacheStub, false)

    :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
      entries: %{},
      prop_params: %{},
      windows: %{@window_id => Query.normalize(Module2)}
    })

    wait_for_process_cleanup(ResultStore)
    start_supervised!(ResultStore)

    wait_for_process_cleanup(Evaluator.registry())
    start_supervised!({Registry, keys: :unique, name: Evaluator.registry()})

    wait_for_process_cleanup(Evaluators)
    start_supervised!(Evaluators)

    :ok
  end

  # An evaluator reads from its own process, which the sandbox owner must let in - otherwise it
  # would reach the pool rather than the transaction this test is writing into.
  defp allow(evaluator) do
    DBConnection.Ownership.ownership_allow(DB.pool_name(), self(), evaluator, [])
  end

  describe "live/0" do
    test "returns nothing while no window is held" do
      assert live() == []
    end

    test "returns a held window with the term it downloads" do
      subscribe(@window_id, self())

      assert live() == [{@window_id, Query.normalize(Module2)}]
    end

    # A live reload can drop a window while its evaluator is still running, and a window with no
    # term left is one no query downloads any more - the scoper has nothing to match it against.
    test "leaves out a window the current build no longer downloads" do
      subscribe(@window_id, self())

      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        prop_params: %{},
        windows: %{}
      })

      assert live() == []
    end

    # The evaluator stops itself once its last subscriber goes, and the registry drops the entry
    # on its own monitor - which fires independently of the evaluator's exit, so the answer is
    # waited for rather than read the instant the process dies.
    test "leaves out a window once its last session goes away" do
      holder = spawn(fn -> Process.sleep(:infinity) end)
      {:ok, _evaluator, 0} = subscribe(@window_id, holder)

      assert live() != []

      Process.exit(holder, :kill)

      wait_until(fn -> live() == [] end)
    end
  end

  describe "subscribe/2" do
    test "starts the evaluator the first session wants" do
      assert {:ok, evaluator, 0} = subscribe(@window_id, self())

      assert Process.alive?(evaluator)
      assert [{^evaluator, _value}] = Registry.lookup(Evaluator.registry(), @window_id)
    end

    test "joins the evaluator a session already started" do
      {:ok, first, 0} = subscribe(@window_id, self())

      assert {:ok, second, 0} =
               subscribe(@window_id, spawn_link(fn -> Process.sleep(:infinity) end))

      assert second == first
    end

    test "tells a session that joined about the rounds that follow" do
      {:ok, evaluator, 0} = subscribe(@window_id, self())
      allow(evaluator)

      Evaluator.round(@window_id, [])

      assert_receive {:round, @window_id, 1, [], nil}
    end

    test "tells both sessions of one window about the same round" do
      test_pid = self()
      other = spawn_link(fn -> forward_rounds(test_pid) end)

      {:ok, evaluator, 0} = subscribe(@window_id, self())
      {:ok, ^evaluator, 0} = subscribe(@window_id, other)
      allow(evaluator)

      Evaluator.round(@window_id, [])

      assert_receive {:round, @window_id, 1, [], nil}
      assert_receive {:forwarded, {:round, @window_id, 1, [], nil}}
    end

    # The evaluator a session loses the start race to can lose its own last subscriber before the
    # loser manages to join it. There is then nothing to join, and the window wants starting again
    # - the session asking must not be taken down for having asked a moment too late.
    test "starts the window again when the evaluator it lost the race to has gone" do
      start_supervised!({VanishingEvaluator, window_id: @window_id})

      assert {:ok, evaluator, 0} = subscribe(@window_id, self())

      assert Process.alive?(evaluator)
      assert [{^evaluator, _value}] = Registry.lookup(Evaluator.registry(), @window_id)
    end

    test "answers that there is no window for an id nothing downloads" do
      assert subscribe("w_unknown", self()) == :no_window
    end

    test "starts nothing for an id nothing downloads" do
      subscribe("w_unknown", self())

      assert DynamicSupervisor.count_children(Evaluators).active == 0
    end
  end

  defp forward_rounds(test_pid) do
    receive do
      message ->
        send(test_pid, {:forwarded, message})

        forward_rounds(test_pid)
    end
  end
end
