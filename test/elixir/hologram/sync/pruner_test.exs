defmodule Hologram.Sync.PrunerTest do
  # async: false - see Hologram.DB.OutboxTest, which prunes too and is sync for the same reason:
  # one advisory lock for the whole database, held to the end of whichever test took it. This
  # module is the greedier of the two, running a pruner that wakes every few milliseconds.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Sync.Pruner

  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Sync.Pruner

  @entity_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"

  # Long enough that the timer never fires on its own: a round racing the end of a test prunes on
  # the sandbox owner's connection while it is being taken away, which drops the connection and
  # takes the test's transaction with it. Rounds are asked for here instead.
  @idle_interval_ms :timer.minutes(10)

  @waking_interval_ms 50

  @prune_timeout_ms 2_000

  defp prune_now(pruner) do
    send(pruner, :prune)

    # Returns only once the round has been handled, this call being queued behind it - which is
    # what makes the assertions after it read a finished prune rather than a hopeful one.
    :sys.get_state(pruner)

    :ok
  end

  defp remaining do
    statement = ~s|SELECT count(*) FROM "hologram_system"."outbox"|

    {:ok, %Postgrex.Result{rows: [[count]]}} = Connection.query(statement)

    count
  end

  defp seed_aged(seconds_ago) do
    statement = """
    INSERT INTO "hologram_system"."outbox"
      ("op", "type", "entity_id", "tx", "model_hash", "inserted_at")
    VALUES ('del_entity', 'Hologram.Test.Fixtures.Entity.Module2', $1, $2, 'seeded',
            now() - make_interval(secs => $3::double precision))
    """

    params = [Codec.encode(@entity_id, :uuid), 200, seconds_ago]

    {:ok, _result} = Connection.query(statement, params)

    :ok
  end

  # The pruner deletes from its own process, which the sandbox owner must let in - otherwise it
  # reaches the pool rather than the transaction this test wrote into, and finds nothing to prune.
  defp start_pruner!(opts) do
    opts = Keyword.put_new(opts, :interval_ms, @idle_interval_ms)

    pruner = start_supervised!({Pruner, opts}, id: :pruner)

    DBConnection.Ownership.ownership_allow(DB.pool_name(), self(), pruner, [])

    pruner
  end

  describe "start_link/1" do
    test "prunes nothing at start, so every node of a deploy does not ask at once" do
      seed_aged(3_600)

      start_pruner!(retention_seconds: 60)

      assert remaining() == 1
    end

    test "touches no database while starting, so it can be supervised beside the pool" do
      assert {:ok, state} = init(interval_ms: @idle_interval_ms, retention_seconds: 60)

      assert state.retention_seconds == 60
    end

    test "keeps the log for a week unless told otherwise" do
      assert {:ok, state} = init([])

      assert state.retention_seconds == 7 * 24 * 60 * 60
    end

    test "wakes once an hour unless told otherwise" do
      assert {:ok, state} = init([])

      assert state.interval_ms == :timer.hours(1)
    end
  end

  describe "handle :prune" do
    test "removes the effects past the retention window" do
      seed_aged(3_600)

      pruner = start_pruner!(retention_seconds: 60)

      prune_now(pruner)

      assert remaining() == 0
    end

    test "keeps the effects inside it" do
      seed_aged(30)

      pruner = start_pruner!(retention_seconds: 60)

      prune_now(pruner)

      assert remaining() == 1
    end

    test "keeps waking after a round, rather than pruning once" do
      start_pruner!(interval_ms: @waking_interval_ms, retention_seconds: 60)

      seed_aged(3_600)
      wait_until(fn -> remaining() == 0 end, @prune_timeout_ms)

      # Written after the first round, so only a second one can remove it.
      seed_aged(3_600)
      wait_until(fn -> remaining() == 0 end, @prune_timeout_ms)

      # Stopped before the test ends, so no round is in flight while the sandbox is taken away.
      stop_supervised!(:pruner)

      assert remaining() == 0
    end
  end
end
