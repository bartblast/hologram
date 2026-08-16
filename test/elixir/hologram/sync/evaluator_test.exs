defmodule Hologram.Sync.EvaluatorTest do
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Sync.Evaluator

  alias Hologram.DB
  alias Hologram.Entity
  alias Hologram.Query
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.ResultStore
  alias Hologram.Test.Fixtures.Entity.Module2

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
      assert_receive {:round, @window_id, 1, _transactions}

      assert %{ids: ids, rows: rows} = ResultStore.fetch(@window_id, 1)
      assert MapSet.member?(ids, entity.id)
      assert rows[entity.id].c == "first"

      assert Process.alive?(evaluator)
    end

    test "counts a version per round" do
      create("first")
      start_evaluator!([])

      round(@window_id, transactions())
      assert_receive {:round, @window_id, 1, _first}

      round(@window_id, transactions())
      assert_receive {:round, @window_id, 2, _second}

      assert ResultStore.versions(@window_id) == [2, 1]
    end

    test "reads the rows as they stand at the round rather than as they stood before" do
      start_evaluator!([])

      round(@window_id, transactions())
      assert_receive {:round, @window_id, 1, _first}

      entity = create("written between rounds")

      round(@window_id, transactions())
      assert_receive {:round, @window_id, 2, _second}

      assert %{rows: rows} = ResultStore.fetch(@window_id, 2)
      assert rows[entity.id].c == "written between rounds"
    end

    test "tells subscribers which round to read, never the rows themselves" do
      create("first")
      start_evaluator!([])

      round(@window_id, transactions())

      assert_receive {:round, window_id, version, handed_transactions}
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

      assert_receive {:round, @window_id, 1, _mine}
      assert_receive {:forwarded, {:round, @window_id, 1, _theirs}}
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

      assert subscribe(@window_id, other) == :ok

      round(@window_id, transactions())

      assert_receive {:forwarded, {:round, @window_id, 1, _transactions}}
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

      assert_receive {:round, @window_id, 1, _transactions}
      refute_receive {:round, @window_id, 1, _duplicate}, 100
    end

    test "answers that there is no evaluator for a window nobody holds" do
      assert subscribe("w_unheld", self()) == :no_evaluator
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

      assert_receive {:round, @window_id, 1, _transactions}
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
