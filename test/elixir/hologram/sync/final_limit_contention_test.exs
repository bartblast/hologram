defmodule Hologram.Sync.FinalLimitContentionTest do
  # The limit reads which saves are running from PostgreSQL's lock table, so what it answers depends
  # on real sessions committing, rolling back and dying, which the sandboxed suite can't give.
  #
  # async: false - every test of the tier opens raw sessions beside its scratch connection, so the
  # tier's modules run one at a time to keep the server's connection count bounded.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import ExUnit.CaptureLog, only: [with_log: 1]

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Oplog
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Sync.FinalLimit

  @append ~s|INSERT INTO "hologram_system"."oplog" ("op", "type", "entity_id", "model_hash") | <>
            ~s|VALUES ('del_entity', 'Task', gen_random_uuid(), 'hash') RETURNING "seq"|

  defp advance(scratch, state), do: route(scratch, fn -> FinalLimit.advance(state) end)

  defp committed_serial(scratch) do
    {:ok, %Postgrex.Result{rows: [[serial]]}} =
      route(scratch, fn -> Connection.query(@append) end)

    serial
  end

  defp flip_run(session) do
    Postgrex.query!(
      session,
      ~s|UPDATE "hologram_system"."server_run" SET "run" = gen_random_uuid()|,
      []
    )

    receive do
      :stop -> :ok
    after
      0 -> flip_run(session)
    end
  end

  defp limit_after(scratch, state) do
    scratch
    |> advance(state)
    |> FinalLimit.limit()
  end

  # One save on the given session: it runs the given statements, tells the given process its serial
  # and its backend, and ends the way that process says.
  defp run_save(session, statements, test_pid) do
    Postgrex.transaction(
      session,
      fn tx ->
        results = Enum.map(statements, &Postgrex.query!(tx, &1, []))
        %Postgrex.Result{rows: [[backend]]} = Postgrex.query!(tx, "SELECT pg_backend_pid()", [])

        send(test_pid, {:save, last_value(results), backend})

        receive do
          :commit -> :committed
          :roll_back -> Postgrex.rollback(tx, :rolled_back)
        end
      end,
      timeout: :infinity
    )
  end

  # A save on a session of its own.
  defp start_save(scratch_opts, statements \\ [@append]) do
    test_pid = self()

    Task.async(fn ->
      {:ok, session} = Postgrex.start_link(scratch_opts)

      run_save(session, statements, test_pid)
    end)
  end

  defp last_value(results) do
    case List.last(results) do
      %Postgrex.Result{rows: [[value]]} -> value
      _no_value -> nil
    end
  end

  defp await_save do
    assert_receive {:save, serial, backend}, 5_000

    {serial, backend}
  end

  # Whether a read named no run while the row kept moving, within the given number of tries.
  defp reads_a_moving_run?(0), do: false

  defp reads_a_moving_run?(tries) do
    case Oplog.serials_in_flight() do
      {_high, _running, nil} -> true
      _same_run -> reads_a_moving_run?(tries - 1)
    end
  end

  setup %{scratch: scratch} do
    route(scratch, fn -> SchemaReconciler.reconcile(DB.reconciliation_context()) end)

    :ok
  end

  test "starts from 0 on a log that has handed out nothing", %{scratch: scratch} do
    assert limit_after(scratch, FinalLimit.new()) == 0
  end

  test "reaches a serial whose save committed", %{scratch: scratch} do
    serial = committed_serial(scratch)

    assert limit_after(scratch, FinalLimit.new()) == serial
  end

  test "stays below a running save until it commits", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    before = committed_serial(scratch)
    state = advance(scratch, FinalLimit.new())

    save = start_save(scratch_opts)
    {serial, _backend} = await_save()

    waiting = advance(scratch, state)

    assert FinalLimit.limit(waiting) == before
    assert FinalLimit.waiting?(waiting)

    send(save.pid, :commit)
    assert {:ok, :committed} = Task.await(save)

    finished = advance(scratch, waiting)

    assert FinalLimit.limit(finished) == serial
    refute FinalLimit.waiting?(finished)
  end

  test "doesn't wait for a save that rolled back, and stays at the last entry", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    before = committed_serial(scratch)
    state = advance(scratch, FinalLimit.new())

    save = start_save(scratch_opts)
    {_serial, _backend} = await_save()

    waiting = advance(scratch, state)
    assert FinalLimit.waiting?(waiting)

    send(save.pid, :roll_back)
    assert {:error, :rolled_back} = Task.await(save)

    finished = advance(scratch, waiting)

    assert FinalLimit.limit(finished) == before
    refute FinalLimit.waiting?(finished)
  end

  test "doesn't wait for a save whose connection was killed, and stays at the last entry", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    before = committed_serial(scratch)
    state = advance(scratch, FinalLimit.new())

    save = start_save(scratch_opts)
    {_serial, backend} = await_save()

    waiting = advance(scratch, state)
    assert FinalLimit.waiting?(waiting)

    {:ok, _result} =
      route(scratch, fn -> Connection.query("SELECT pg_terminate_backend($1)", [backend]) end)

    wait_until(fn ->
      settled = advance(scratch, waiting)

      not FinalLimit.waiting?(settled)
    end)

    assert limit_after(scratch, waiting) == before

    Task.shutdown(save, :brutal_kill)
  end

  test "doesn't wait for a save whose only serial was in a savepoint it rolled back", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    before = committed_serial(scratch)

    save =
      start_save(scratch_opts, [
        "SAVEPOINT undone",
        @append,
        "ROLLBACK TO SAVEPOINT undone",
        "SELECT 1"
      ])

    await_save()

    finished = advance(scratch, FinalLimit.new())

    assert FinalLimit.limit(finished) == before
    refute FinalLimit.waiting?(finished)

    send(save.pid, :commit)
    assert {:ok, :committed} = Task.await(save)
  end

  test "waits for a save that took a serial again after rolling a savepoint back", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    save =
      start_save(scratch_opts, [
        "SAVEPOINT undone",
        @append,
        "ROLLBACK TO SAVEPOINT undone",
        @append
      ])

    {serial, _backend} = await_save()

    waiting = advance(scratch, FinalLimit.new())

    assert FinalLimit.limit(waiting) == nil

    send(save.pid, :commit)
    assert {:ok, :committed} = Task.await(save)

    assert limit_after(scratch, waiting) == serial
  end

  test "tells a save from the next one on the same connection", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    test_pid = self()

    saves =
      Task.async(fn ->
        {:ok, session} = Postgrex.start_link(scratch_opts)

        {:ok, :committed} = run_save(session, [@append], test_pid)
        {:ok, :committed} = run_save(session, [@append], test_pid)
      end)

    {first, backend} = await_save()

    waiting = advance(scratch, FinalLimit.new())
    assert FinalLimit.limit(waiting) == nil

    send(saves.pid, :commit)
    {_second, ^backend} = await_save()

    assert limit_after(scratch, waiting) == first

    send(saves.pid, :commit)
    Task.await(saves)
  end

  test "refuses to run inside a transaction", %{scratch: scratch} do
    assert_raise ArgumentError, ~r/inside a transaction/, fn ->
      route(scratch, fn ->
        Connection.transaction(fn -> FinalLimit.advance(FinalLimit.new()) end)
      end)
    end
  end

  test "puts the run's row back after it was emptied, and takes the new run as a restart", %{
    scratch: scratch
  } do
    serial = committed_serial(scratch)
    state = advance(scratch, FinalLimit.new())

    {:ok, _result} =
      route(scratch, fn -> Connection.query(~s|DELETE FROM "hologram_system"."server_run"|) end)

    after_empty = advance(scratch, state)

    assert after_empty == state

    moved = advance(scratch, after_empty)

    assert moved.run != state.run
    assert FinalLimit.limit(moved) == serial
  end

  test "fills the view naming the copy of the database once a restore left it empty", %{
    scratch: scratch
  } do
    serial = committed_serial(scratch)

    {:ok, _result} =
      route(scratch, fn ->
        Connection.query(
          ~s|REFRESH MATERIALIZED VIEW "hologram_system"."database_copy" WITH NO DATA|
        )
      end)

    state = FinalLimit.new()

    assert advance(scratch, state) == state
    assert limit_after(scratch, state) == serial
  end

  test "adds no run row while a restore has the table without its key", %{scratch: scratch} do
    route(scratch, fn ->
      {:ok, _result} =
        Connection.query(
          ~s|ALTER TABLE "hologram_system"."server_run" DROP CONSTRAINT "server_run_pkey"|
        )

      {:ok, _result} = Connection.query(~s|DELETE FROM "hologram_system"."server_run"|)

      assert Oplog.ensure_server_run() == :no_key

      assert {:ok, %Postgrex.Result{rows: [[0]]}} =
               Connection.query(~s|SELECT count(*) FROM "hologram_system"."server_run"|)
    end)
  end

  test "warns once while the run's table stays without its key, and again after it's back", %{
    scratch: scratch
  } do
    drop_key = ~s|ALTER TABLE "hologram_system"."server_run" DROP CONSTRAINT "server_run_pkey"|
    add_key = ~s|ALTER TABLE "hologram_system"."server_run" ADD PRIMARY KEY ("only_row")|
    empty = ~s|DELETE FROM "hologram_system"."server_run"|

    run = fn statement ->
      {:ok, _result} = route(scratch, fn -> Connection.query(statement) end)
    end

    warnings = fn log -> length(String.split(log, "has no primary key")) - 1 end

    run.(drop_key)
    run.(empty)

    {state, log} =
      with_log(fn ->
        scratch
        |> advance(FinalLimit.new())
        |> then(&advance(scratch, &1))
        |> then(&advance(scratch, &1))
      end)

    assert warnings.(log) == 1
    assert state.run_key_missing

    run.(add_key)

    # The first round puts the row back, and the next reads it.
    recovered =
      scratch
      |> advance(state)
      |> then(&advance(scratch, &1))

    refute recovered.run_key_missing

    run.(drop_key)
    run.(empty)

    {_state, second_log} = with_log(fn -> advance(scratch, recovered) end)

    assert warnings.(second_log) == 1
  end

  test "keeps the run's table unlogged, so a crash empties it", %{scratch: scratch} do
    statement = """
    SELECT c.relpersistence FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hologram_system' AND c.relname = 'server_run'
    """

    assert {:ok, %Postgrex.Result{rows: [["u"]]}} =
             route(scratch, fn -> Connection.query(statement) end)
  end

  test "names the server's start time in the run, whatever the session's settings", %{
    scratch: scratch
  } do
    start_time = ~s|SELECT (extract(epoch FROM pg_postmaster_start_time()) * 1000000)::bigint|

    route(scratch, fn ->
      {:ok, %Postgrex.Result{rows: [[started]]}} = Connection.query(start_time)
      {_high, _running, run} = Oplog.serials_in_flight()

      {:ok, _result} = Connection.query("SET TimeZone = 'Asia/Tokyo'")
      {:ok, _result} = Connection.query("SET DateStyle = 'German'")

      assert {_high, _running, ^run} = Oplog.serials_in_flight()
      assert [_log_id, started_text] = String.split(run, "/")
      assert started_text == Integer.to_string(started)
    end)
  end

  test "reads a new run once the log's file is replaced, as restoring a dump does", %{
    scratch: scratch
  } do
    route(scratch, fn ->
      {_high, _running, run} = Oplog.serials_in_flight()

      {:ok, _result} = Connection.query(~s|TRUNCATE "hologram_system"."oplog"|)

      {_high, _running, replaced} = Oplog.serials_in_flight()

      assert Oplog.run_log_id(replaced) != Oplog.run_log_id(run)
    end)
  end

  test "keeps the log id across a clean restart, which only moves the start time", %{
    scratch: scratch
  } do
    route(scratch, fn ->
      {_high, _running, run} = Oplog.serials_in_flight()

      assert Oplog.run_log_id(run) == Oplog.log_id()
    end)
  end

  # Every node finding the same loss rotates it, and the ones after the first find it moved.
  test "rotates the log id once between nodes finding the same loss", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    log_id = route(scratch, &Oplog.log_id/0)
    test_pid = self()

    first =
      Task.async(fn ->
        {:ok, session} = Postgrex.start_link(scratch_opts)

        Postgrex.transaction(session, fn tx ->
          rotated =
            Connection.with_connection(tx, fn ->
              :ok = Oplog.rotate_log_id(log_id)
              Oplog.log_id()
            end)

          send(test_pid, {:rotated, rotated})

          receive do
            :commit -> :committed
          end
        end)
      end)

    assert_receive {:rotated, rotated}, 5_000

    second =
      Task.async(fn ->
        {:ok, session} = Postgrex.start_link(scratch_opts)

        Connection.with_connection(session, fn -> Oplog.rotate_log_id(log_id) end)
      end)

    :ok = wait_for_blocked_sessions(scratch_opts, 1)

    send(first.pid, :commit)
    assert {:ok, :committed} = Task.await(first)
    assert Task.await(second) == :ok

    assert route(scratch, &Oplog.log_id/0) == rotated
    refute rotated == log_id
  end

  test "names no run when the two reads were in different ones", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    flipper =
      Task.async(fn ->
        {:ok, session} = Postgrex.start_link(scratch_opts)

        flip_run(session)
      end)

    assert route(scratch, fn -> reads_a_moving_run?(2_000) end)

    send(flipper.pid, :stop)
    Task.await(flipper)
  end

  test "reads the highest serial before the saves running", %{scratch: scratch} do
    reader =
      Task.async(fn ->
        receive do
          :read -> route(scratch, fn -> Oplog.serials_in_flight() end)
        end
      end)

    :erlang.trace(reader.pid, true, [:call])
    :erlang.trace_pattern({Connection, :query, 3}, true, [:local])

    send(reader.pid, :read)
    Task.await(reader)

    :erlang.trace_pattern({Connection, :query, 3}, false, [:local])

    assert_received {:trace, _pid, :call, {Connection, :query, [first | _args]}}
    assert_received {:trace, _pid, :call, {Connection, :query, [second | _args]}}

    assert first =~ "oplog_seq_seq"
    assert second =~ "pg_locks"
  end

  test "doesn't wait for a transaction that never touches the log", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    foreign = start_save(scratch_opts, ["SELECT pg_current_xact_id()::text"])
    {_xact_id, _backend} = await_save()

    serial = committed_serial(scratch)

    assert limit_after(scratch, FinalLimit.new()) == serial

    send(foreign.pid, :commit)
    assert {:ok, :committed} = Task.await(foreign)
  end

  test "leaves out the saves of another database", %{
    scratch: scratch,
    scratch_opts: scratch_opts
  } do
    other_opts = Keyword.put(scratch_opts, :database, "postgres")
    {:ok, other} = Postgrex.start_link(other_opts)
    test_pid = self()

    holder =
      Task.async(fn ->
        Postgrex.transaction(
          other,
          fn tx ->
            Postgrex.query!(tx, "SELECT pg_advisory_xact_lock_shared($1)", [
              Oplog.serial_lock_key()
            ])

            send(test_pid, :holding)

            receive do
              :release -> :ok
            end
          end,
          timeout: :infinity
        )
      end)

    assert_receive :holding, 5_000

    serial = committed_serial(scratch)

    assert limit_after(scratch, FinalLimit.new()) == serial

    send(holder.pid, :release)
    assert {:ok, :ok} = Task.await(holder)
  end
end
