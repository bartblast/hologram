defmodule Hologram.Sync.EvaluatorTest do
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Sync.Evaluator

  alias Hologram.DB
  alias Hologram.Entity
  alias Hologram.Query
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.ResultStore
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Sync.VanishingEvaluator

  @window_id "w_7f3a"

  setup do
    wait_for_process_cleanup(ResultStore)
    start_supervised!(ResultStore)

    wait_for_process_cleanup(registry())
    start_supervised!({Registry, keys: :unique, name: registry()})

    :ok
  end

  defp create(title) do
    Module2
    |> Entity.new(a: true, c: title)
    |> DB.create()
  end

  # The evaluator reads from its own process, which the sandbox owner must let in - otherwise it
  # would reach the pool rather than the transaction this test is writing into.
  defp start_evaluator!(opts) do
    opts =
      opts
      |> Keyword.put_new(:window_id, @window_id)
      |> Keyword.put_new(:term, Query.normalize(Module2))
      |> Keyword.put_new(:subscribers, [self()])

    pid = start_supervised!({Evaluator, opts})

    DBConnection.Ownership.ownership_allow(DB.pool_name(), self(), pid, [])

    pid
  end

  defp transactions do
    [{200, [%{op: :patch_entity, type: Module2}]}]
  end

  describe "round/2" do
    test "writes what the window holds now as its next version" do
      entity = create("first")
      evaluator = start_evaluator!([])

      round(@window_id, transactions())
      assert_receive {:round, @window_id, 1, _transactions, _place}

      assert %{ids: ids, rows: rows} = ResultStore.fetch(@window_id, 1)
      assert MapSet.member?(ids, entity.id)
      assert rows[entity.id].c == "first"

      assert Process.alive?(evaluator)
    end

    test "counts a version per round" do
      create("first")
      start_evaluator!([])

      round(@window_id, transactions())
      assert_receive {:round, @window_id, 1, _first, _place}

      round(@window_id, transactions())
      assert_receive {:round, @window_id, 2, _second, _place}

      assert ResultStore.versions(@window_id) == [2, 1]
    end

    test "reads the rows as they stand at the round rather than as they stood before" do
      start_evaluator!([])

      round(@window_id, transactions())
      assert_receive {:round, @window_id, 1, _first, _place}

      entity = create("written between rounds")

      round(@window_id, transactions())
      assert_receive {:round, @window_id, 2, _second, _place}

      assert %{rows: rows} = ResultStore.fetch(@window_id, 2)
      assert rows[entity.id].c == "written between rounds"
    end

    test "hands subscribers the place the batch was read from" do
      create("first")
      start_evaluator!([])

      round(@window_id, transactions(), {200, 0})

      assert_receive {:round, @window_id, 1, _transactions, {200, 0}}
    end

    # Suspending is what makes the pile-up deterministic: both rounds queue while the evaluator
    # cannot run, and resuming makes the first drain the second into one merged run.
    test "answers piled-up rounds with one run claiming the earliest place" do
      create("first")
      evaluator = start_evaluator!([])

      first_batch = [{200, [%{op: :patch_entity, type: Module2}]}]
      second_batch = [{300, [%{op: :del_entity, type: Module2}]}]

      :ok = :sys.suspend(evaluator)
      round(@window_id, first_batch, {200, 0})
      round(@window_id, second_batch, {300, 0})
      :ok = :sys.resume(evaluator)

      # Merged rather than dropped: the run reads fresh state, but the transactions name WHICH
      # attributes moved, and losing the second batch's would lose its patches.
      assert_receive {:round, @window_id, 1, merged, {200, 0}}
      assert merged == first_batch ++ second_batch

      refute_receive {:round, @window_id, _version, _more, _place}, 100
    end

    test "claims no place for a round a session asked for rather than the log" do
      create("first")
      start_evaluator!([])

      round(@window_id, [])

      assert_receive {:round, @window_id, 1, [], nil}
    end

    test "tells subscribers which round to read, never the rows themselves" do
      create("first")
      start_evaluator!([])

      round(@window_id, transactions())

      assert_receive {:round, window_id, version, handed_transactions, _place}
      assert window_id == @window_id
      assert version == 1
      assert handed_transactions == transactions()
    end

    test "tells every subscriber" do
      create("first")
      test_pid = self()

      other = spawn_link(fn -> forward_rounds(test_pid) end)

      start_evaluator!(subscribers: [self(), other])

      round(@window_id, transactions())

      assert_receive {:round, @window_id, 1, _mine, _place}
      assert_receive {:forwarded, {:round, @window_id, 1, _theirs, _place}}
    end

    test "does nothing for a window no evaluator holds" do
      assert round("w_unheld", transactions()) == :ok
    end
  end

  describe "subscribe/2" do
    test "tells a subscriber added after the start about the rounds that follow" do
      create("first")
      test_pid = self()

      other = spawn_link(fn -> forward_rounds(test_pid) end)

      start_evaluator!([])

      assert subscribe(@window_id, other) == {:ok, 0}

      round(@window_id, transactions())

      assert_receive {:forwarded, {:round, @window_id, 1, _transactions, _place}}
    end

    # Storing subscribers by pid already keeps the sends single - what asking twice would
    # otherwise leave behind is a second monitor of the same process, watched forever.
    test "watches a subscriber once however often it asks" do
      create("first")
      evaluator = start_evaluator!(subscribers: [])

      subscribe(@window_id, self())
      subscribe(@window_id, self())

      assert {:monitors, monitors} = Process.info(evaluator, :monitors)
      assert monitors == [{:process, self()}]

      round(@window_id, transactions())

      assert_receive {:round, @window_id, 1, _transactions, _place}
      refute_receive {:round, @window_id, 1, _duplicate, _place}, 100
    end

    test "answers that there is no evaluator for a window nobody holds" do
      assert subscribe("w_unheld", self()) == :no_evaluator
    end

    # A registry entry outlives the process it names by however long the registry takes to hear it
    # died, so this window is real: suspending the registry holds it open rather than inventing it.
    # A lookup there hands back a pid with nothing behind it, and calling that used to take down
    # whoever asked - a session, whose client then loses its stream.
    test "answers the same when the registry still lists a process that has stopped" do
      evaluator = start_evaluator!([])

      partitions =
        registry()
        |> Supervisor.which_children()
        |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)

      Enum.each(partitions, &:sys.suspend/1)

      ref = Process.monitor(evaluator)
      Process.exit(evaluator, :kill)
      assert_receive {:DOWN, ^ref, :process, ^evaluator, :killed}

      assert [{^evaluator, _value}] = Registry.lookup(registry(), @window_id)
      assert subscribe(@window_id, self()) == :no_evaluator

      Enum.each(partitions, &:sys.resume/1)
    end

    test "answers the same when the evaluator stops while it is being asked" do
      start_supervised!({VanishingEvaluator, window_id: @window_id})

      assert subscribe(@window_id, self()) == :no_evaluator
    end
  end

  describe "start_link/1" do
    # An evaluator that is killed, or whose query raises, never reaches the clause that clears its
    # rows - and its replacement counts rounds from zero again, so every version left behind is one
    # nothing can ask for. Left alone they wait for a count that may never climb past them: the
    # replacement's own pruning only reaches versions inside its own range.
    test "clears what an evaluator that never got to clean up left behind" do
      create("first")

      killed = start_evaluator!([])
      round(@window_id, transactions())
      wait_for_result_store_write()

      ref = Process.monitor(killed)
      Process.exit(killed, :kill)
      assert_receive {:DOWN, ^ref, :process, ^killed, :killed}

      # Still there, which is what makes the next line worth asserting.
      assert ResultStore.versions(@window_id) == [1]

      # No wait for the registry to drop the killed one's entry: registering a name whose owner is
      # dead takes it over rather than being refused, which is the same thing that lets a
      # supervisor restart any via-named child at all. Only LOOKUP sees the stale entry.
      #
      # The killed one is temporary, so the supervisor has already dropped it and its id is free.
      start_evaluator!([])

      assert ResultStore.versions(@window_id) == []
    end
  end

  describe "handle :DOWN" do
    test "stops once its last subscriber goes away, forgetting what it held" do
      create("first")

      subscriber = spawn(fn -> Process.sleep(:infinity) end)
      evaluator = start_evaluator!(subscribers: [subscriber])
      evaluator_ref = Process.monitor(evaluator)

      round(@window_id, transactions())
      wait_for_result_store_write()

      Process.exit(subscriber, :kill)

      assert_receive {:DOWN, ^evaluator_ref, :process, ^evaluator, :normal}
      assert ResultStore.versions(@window_id) == []
    end

    test "keeps running while another subscriber holds it" do
      create("first")

      leaving = spawn(fn -> Process.sleep(:infinity) end)
      evaluator = start_evaluator!(subscribers: [self(), leaving])

      Process.exit(leaving, :kill)

      round(@window_id, transactions())

      assert_receive {:round, @window_id, 1, _transactions, _place}
      assert Process.alive?(evaluator)
    end
  end

  defp forward_rounds(test_pid) do
    receive do
      message ->
        send(test_pid, {:forwarded, message})

        forward_rounds(test_pid)
    end
  end

  defp wait_for_result_store_write do
    if ResultStore.versions(@window_id) == [] do
      Process.sleep(1)

      wait_for_result_store_write()
    end
  end
end
