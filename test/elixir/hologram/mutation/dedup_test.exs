defmodule Hologram.Mutation.DedupTest do
  # Two arrivals of ONE batch, at the same moment, on two sessions - a client that retried before
  # the first answer came back, or two nodes handed the same request.
  #
  # What makes the answer a single one is the record's primary key: the first arrival claims it
  # inside its transaction, and the second BLOCKS on that key until the first commits, then finds
  # the row there and answers from it. Neither half of that can be seen under the sandboxed case,
  # where every test is one never-committed transaction on one connection - so this test lives in
  # the scratch tier, with a database of its own and a real session per actor.
  #
  # async: false - the tier's modules run one at a time, since each opens raw sessions beside its
  # scratch connection.
  use Hologram.Test.ScratchDatabaseCase, async: false

  alias Hologram.DB.Connection
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Mutation
  alias Hologram.Mutation.Record
  alias Hologram.Server

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  defp claim_holder(replica_id, test_pid) do
    fn -> Connection.transaction(fn -> hold_claim(replica_id, test_pid) end) end
  end

  defp hold_claim(replica_id, test_pid) do
    Record.claim!(replica_id, 1, nil, Model.hash())

    send(test_pid, :claimed)

    receive do
      :go -> :ok
    end

    Record.complete!(replica_id, 1, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}})
  end

  defp on_own_session(scratch_opts, fun) do
    {:ok, session} = Postgrex.start_link(scratch_opts)

    route(session, fun)
  end

  defp record_row_count do
    {:ok, %Postgrex.Result{rows: [[count]]}} =
      Connection.query(~s|SELECT count(*) FROM "hologram_system"."mutation"|)

    count
  end

  # The first arrival, holding its claim open until the test lets it finish - so the second really
  # does meet a claim in flight rather than one already committed.
  defp start_first_arrival(replica_id, scratch_opts, test_pid) do
    Task.async(fn -> on_own_session(scratch_opts, claim_holder(replica_id, test_pid)) end)
  end

  # A batch of no writes: nothing here needs an entity table, and what is under test is the claim
  # rather than anything the writes do.
  defp start_second_arrival(replica_id, scratch_opts) do
    envelope = %{
      "instance_id" => "i1",
      "replica_id" => replica_id,
      "model_hash" => Model.hash(),
      "seq" => 1,
      "writes" => []
    }

    Task.async(fn ->
      on_own_session(scratch_opts, fn -> Mutation.run(envelope, %Server{}) end)
    end)
  end

  # A poller and a session parked on a lock look the same to a task that has not returned, so the
  # wait is asserted where it is visible: Postgres itself, naming what is being waited for. A second
  # arrival blocked on the record's key waits on the FIRST ARRIVAL'S TRANSACTION ID - the key is
  # taken by a row nobody else can see yet, so there is nothing to wait on but the transaction that
  # wrote it.
  #
  # Scoped to this database and excluding the observer, because pg_stat_activity is the whole
  # server: the rest of the suite runs against another database at the same moment.
  defp wait_for_blocked_claim(scratch_opts) do
    {:ok, observer} = Postgrex.start_link(scratch_opts)

    statement = """
    SELECT count(*) FROM pg_catalog.pg_stat_activity
    WHERE "datname" = current_database() AND "wait_event_type" = 'Lock'
      AND "wait_event" = 'transactionid' AND "pid" <> pg_backend_pid()
    """

    wait_until(fn ->
      %Postgrex.Result{rows: [[count]]} = Postgrex.query!(observer, statement, [])

      count == 1
    end)
  end

  test "a concurrent duplicate waits for the first arrival and answers from its record", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    # A virgin database claims itself: both schemas, every system table and the marker.
    route(scratch, fn ->
      Connection.transaction(fn -> SchemaReconciler.ensure_managed!(@context) end)
    end)

    replica_id = Entity.generate_id()

    first = start_first_arrival(replica_id, scratch_opts, self())
    assert_receive :claimed, 5_000

    second = start_second_arrival(replica_id, scratch_opts)

    wait_for_blocked_claim(scratch_opts)

    send(first.pid, :go)

    assert Task.await(first) == {:ok, :ok}

    assert Task.await(second) ==
             {:ok, %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}}

    assert route(scratch, fn -> Record.find(replica_id, 1) end) == %{
             actor_id: nil,
             result: %{"status" => "confirmed", "dropped" => %{}, "kept" => %{}}
           }

    assert route(scratch, fn -> record_row_count() end) == 1
  end
end
