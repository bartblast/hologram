defmodule Hologram.Sync.DispatcherTest do
  # Grouped with Hologram.Sync.ReadEdgeTest - see the reasoning there. Both start a read edge under
  # the one name it registers under, so they must not run at the same time.
  use Hologram.Test.DatabaseCase, async: true, group: :sync_read_edge

  import ExUnit.CaptureLog
  import Hologram.Sync.Dispatcher

  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Oplog
  alias Hologram.Sync.Dispatcher
  alias Hologram.Sync.FinalLimit
  alias Hologram.Sync.ReadEdge
  alias Hologram.Test.Fixtures.Entity.Module2

  @entity_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"
  @target_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e1a"

  # For the tests that only have to see a timer re-arm itself, or a later round find what the first
  # one couldn't.
  @armed_poll_interval_ms 20

  @poll_timeout_ms 2_000

  # A minute ago and a moment more, which is how long a prepared transaction has to hold the limit
  # back before the dispatcher says so.
  @prepared_warning_ms :timer.minutes(1) + 1_000

  # Brings the poll interval within reach and hands over the first poll, whose handler is what arms
  # a timer at the new interval.
  defp arm_polling(dispatcher) do
    :sys.replace_state(dispatcher, &%{&1 | poll_interval_ms: @armed_poll_interval_ms})

    send(dispatcher, :poll)
  end

  # A round of the final limit that takes every serial as final. The real one waits for the saves
  # holding the serial lock, and this test's transaction holds it from its first seed until the
  # sandbox rolls it back, so it would never reach a row a test writes.
  #
  # Lets the dispatcher into the test's transaction first, before its first query. The first round
  # runs as the dispatcher starts, ahead of anything the test does once start_supervised returns,
  # and a query run before the allowance would check out a connection of its own, where none of
  # the test's rows are.
  defp sandbox_advance(opts \\ []) do
    test_pid = self()
    high = Keyword.get(opts, :high)

    running =
      opts
      |> Keyword.get(:running, [])
      |> MapSet.new()

    fn state ->
      DBConnection.Ownership.ownership_allow(DB.pool_name(), test_pid, self(), [])

      {_entry, run} = Oplog.entry_at(0)
      high = high || Oplog.last_serial()

      FinalLimit.advance(
        state,
        run,
        high,
        running,
        &Oplog.last_entry_through/1,
        &Oplog.entry_at/1
      )
    end
  end

  # Given a seq, the entry takes it, as a save that took its serial earlier commits it.
  defp seed(tx, entity_id, seq \\ nil) do
    statement = """
    INSERT INTO "hologram_system"."oplog" ("seq", "op", "type", "entity_id", "tx", "model_hash")
    VALUES (
      COALESCE($3::bigint, #{Oplog.next_seq_sql()}),
      'del_entity', 'Hologram.Test.Fixtures.Entity.Module2', $1, $2, 'seeded'
    )
    RETURNING "seq", "tx", "inserted_at"
    """

    {:ok, %Postgrex.Result{rows: [[seq, tx, inserted_at]]}} =
      Connection.query(statement, [Codec.encode(entity_id, :uuid), tx, seq])

    Oplog.place(%{inserted_at: inserted_at, seq: seq, tx: tx})
  end

  # A serial a save still running took, which it fills once it commits.
  defp take_serial do
    {:ok, %Postgrex.Result{rows: [[seq]]}} = Connection.query("SELECT #{Oplog.next_seq_sql()}")

    seq
  end

  # Every test that starts a dispatcher ends here. A dispatcher borrows the test's connection, so
  # it must not be MID-QUERY when the sandbox takes that connection back: the shutdown signal kills
  # it where it stands, the driver sees its client vanish and drops the connection, and the
  # rollback then finds none to roll back - failing whichever test happened to be last rather than
  # the one that raced. The messages these tests wait for are sent from the MIDDLE of a round, so
  # none of them says the work is over.
  #
  # Not something the teardown can do instead: ExUnit stops what start_supervised started before
  # any on_exit runs, so by then the dispatcher is already gone.
  defp settle(dispatcher) do
    :sys.replace_state(dispatcher, &%{&1 | poll_interval_ms: :timer.minutes(1)})
    :ok = :sys.suspend(dispatcher)

    stop_supervised!(Dispatcher)
  end

  # What a crash or a promoted standby does to the server's run (see
  # `Hologram.DB.Oplog.serials_in_flight/0`), which names a new log id.
  defp crash_server do
    {:ok, _result} =
      Connection.query(~s|UPDATE "hologram_system"."server_run" SET "run" = gen_random_uuid()|)

    :ok
  end

  defp start_dispatcher!(opts) do
    test_pid = self()

    # A round reading nothing is handed on only to say the limit moved, which the tests of what a
    # round reads look past.
    handler = fn
      [], _place, _sent, final_seq ->
        send(test_pid, {:limit_moved, final_seq})

      effects, place, sent, _final_seq ->
        send(test_pid, {:dispatched, effects, place})
        send(test_pid, {:sent, sent})
    end

    opts =
      opts
      |> Keyword.put_new_lazy(:advance, fn -> sandbox_advance() end)
      |> Keyword.put_new(:handler, handler)
      |> Keyword.put_new(:on_loss, fn -> send(test_pid, :lost) end)
      |> Keyword.put_new(:poll_interval_ms, :timer.minutes(1))

    start_supervised!({Dispatcher, opts})
  end

  defp start_read_edge!(remembering \\ nil) do
    read_edge = start_supervised!(ReadEdge)

    if remembering, do: :ok = ReadEdge.put(read_edge, remembering)

    read_edge
  end

  # Stands in for a Postgrex.Notifications process, which answers listen/2 with a reference and
  # would otherwise need a connection of its own. `:answer` is which of the two it gives -
  # `:eventually` is what a real one says while its connection is still opening, the state a
  # connection that starts asynchronously is in for its first moments.
  defmodule NotificationsStub do
    @moduledoc false

    use GenServer

    @spec start_link(keyword) :: GenServer.on_start()
    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl GenServer
    def init(opts), do: {:ok, {opts[:reply_to], Keyword.get(opts, :answer, :ok)}}

    @impl GenServer
    def handle_call({{:listen, channel}, _caller}, _from, {reply_to, answer} = state) do
      send(reply_to, {:listening, channel})

      {:reply, {answer, make_ref()}, state}
    end
  end

  describe "start_link/1" do
    test "starts reading at the final limit when given no cursor" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!([])

      wake(dispatcher)

      refute_receive {:dispatched, _effects, _place}, 100

      settle(dispatcher)
    end

    # The place is taken when the dispatcher starts, not when something first wakes it - and what
    # usually wakes it is the very append a client is waiting for. Taken then, the limit would
    # already be above that append and nothing read from it would hold it, passing it by for
    # good.
    test "takes the final limit as its place at start, rather than at its first wake" do
      place = seed(200, @entity_id)

      dispatcher = start_dispatcher!([])

      assert :sys.get_state(dispatcher).cursor == place

      settle(dispatcher)
    end

    test "takes the place before the first entry at start when the log holds none" do
      dispatcher = start_dispatcher!([])

      assert :sys.get_state(dispatcher).cursor == {0, 0, 0}

      settle(dispatcher)
    end

    # A save running as the dispatcher starts holds the first limit back, and a place taken before
    # it ends could stand above what that save writes.
    test "reads nothing and takes no place until a round finishes" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(advance: sandbox_advance(running: ["a"]))

      wake(dispatcher)

      refute_receive {:dispatched, _effects, _place}, 100
      assert :sys.get_state(dispatcher).cursor == nil

      settle(dispatcher)
    end

    # What a dispatcher replacing a crashed one has to do: the state of the one that died is gone,
    # and starting at the limit would skip the effects it was reading - which the sessions that
    # outlived it would then be carried past, holding a place covering rows they were never sent.
    test "resumes from where the dispatcher it replaces got to" do
      first = seed(200, @entity_id)
      seed(201, @entity_id)

      dispatcher = start_dispatcher!(read_edge: start_read_edge!({first, Oplog.log_id()}))

      assert_receive {:dispatched, [%{tx: 201}], ^first}
      refute_received :lost

      settle(dispatcher)
    end

    # A save running as it starts keeps the first limit back, and the effects above the place it
    # resumed from go out meanwhile, from that place.
    test "hands over the effects above where it resumed from before its first limit" do
      first = seed(200, @entity_id)
      seed(201, @entity_id)
      read_edge = start_read_edge!({first, Oplog.log_id()})

      dispatcher =
        start_dispatcher!(advance: sandbox_advance(running: ["a"]), read_edge: read_edge)

      assert_receive {:dispatched, [%{tx: 201}], ^first}
      assert :sys.get_state(dispatcher).cursor == first
      assert ReadEdge.get(read_edge) == {first, Oplog.log_id()}

      settle(dispatcher)
    end

    # A dispatcher crashing as the database fails over resumes on a server that can have lost the
    # commits it read, which nothing watched for while it was down.
    test "stops the sessions when the place it resumed from is in a log of another id" do
      place = seed(200, @entity_id)
      log_id = Oplog.log_id()
      read_edge = start_read_edge!({place, "0123456789abcdef0123456789abcdef"})

      dispatcher = start_dispatcher!(read_edge: read_edge)

      assert_receive :lost
      refute_received {:dispatched, _effects, _place}
      assert :sys.get_state(dispatcher).cursor == place
      assert ReadEdge.get(read_edge) == {place, log_id}

      settle(dispatcher)
    end

    test "starts at the final limit when nothing was recorded to resume from" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(read_edge: start_read_edge!())

      wake(dispatcher)

      refute_receive {:dispatched, _effects, _place}, 100

      settle(dispatcher)
    end

    test "records where it starts, for whichever dispatcher replaces it" do
      place = seed(200, @entity_id)

      read_edge = start_read_edge!()
      dispatcher = start_dispatcher!(read_edge: read_edge)

      :sys.get_state(dispatcher)

      assert ReadEdge.get(read_edge) == {place, Oplog.log_id()}

      settle(dispatcher)
    end

    test "refuses to start with nowhere to send what it reads" do
      assert_raise KeyError, fn -> init([]) end
    end
  end

  describe ":publish" do
    defp publishing do
      test_pid = self()

      fn seq -> send(test_pid, {:published, seq}) end
    end

    test "publishes nothing final at start with nowhere to resume from, then the first limit" do
      {seq, _tx, _at} = seed(200, @entity_id)

      dispatcher = start_dispatcher!(publish: publishing())

      assert_receive {:published, 0}
      assert_receive {:published, ^seq}

      settle(dispatcher)
    end

    test "publishes the place it resumed from at start" do
      {seq, _tx, _at} = first = seed(200, @entity_id)

      dispatcher =
        start_dispatcher!(
          advance: sandbox_advance(running: ["a"]),
          publish: publishing(),
          read_edge: start_read_edge!({first, Oplog.log_id()})
        )

      assert_receive {:published, ^seq}
      :sys.get_state(dispatcher)
      refute_received {:published, 0}

      settle(dispatcher)
    end

    # A round publishes its limit before it puts its place, so a dispatcher restarted between the
    # two resumes below what queries already read as final.
    test "publishes the limit published before it at start when it is above the place resumed" do
      {seq, _tx, _at} = first = seed(200, @entity_id)
      published_seq = seq + 9

      dispatcher =
        start_dispatcher!(
          advance: sandbox_advance(running: ["a"]),
          publish: publishing(),
          published: fn -> published_seq end,
          read_edge: start_read_edge!({first, Oplog.log_id()})
        )

      assert_receive {:published, ^published_seq}
      :sys.get_state(dispatcher)
      refute_received {:published, ^seq}

      settle(dispatcher)
    end

    test "publishes the place each round moves to" do
      place = seed(200, @entity_id)

      dispatcher = start_dispatcher!(cursor: place, publish: publishing())
      :sys.get_state(dispatcher)

      {seq, _tx, _at} = seed(201, @entity_id)
      wake(dispatcher)

      assert_receive {:published, ^seq}

      settle(dispatcher)
    end

    # A session registering after the round's list reads the published limit as it joins, which
    # covers the round only if the limit was published before the list was taken.
    test "publishes the limit a round reached before handing the round on" do
      place = seed(200, @entity_id)
      test_pid = self()

      handler = fn _effects, _place, _sent, final_seq ->
        send(test_pid, {:handling, final_seq})

        receive do
          :go -> :ok
        end
      end

      dispatcher = start_dispatcher!(cursor: place, handler: handler, publish: publishing())
      :sys.get_state(dispatcher)

      {seq, _tx, _at} = seed(201, @entity_id)
      wake(dispatcher)

      assert_receive {:handling, ^seq}
      assert_received {:published, ^seq}

      send(dispatcher, :go)
      settle(dispatcher)
    end

    test "publishes nothing final once a loss is found" do
      {seq, tx, inserted_at} = seed(200, @entity_id)

      dispatcher =
        start_dispatcher!(cursor: {seq + 5, tx, inserted_at}, publish: publishing())

      assert_receive :lost
      assert_received {:published, 0}

      # The limit worked out after the loss is below the place resumed, and still goes out.
      assert_receive {:published, ^seq}

      settle(dispatcher)
    end
  end

  describe "handle :wake" do
    # The place is what a frame built from this batch may claim a client has reached: replaying
    # from it re-reads the whole batch, and never less.
    test "hands over the place the round read from" do
      place = seed(200, @entity_id)
      seed(201, @entity_id)

      dispatcher = start_dispatcher!(cursor: place)

      assert_receive {:dispatched, [%{tx: 201}], ^place}

      settle(dispatcher)
    end

    test "hands over the effects the round read, in seq order" do
      seed(201, @entity_id)
      seed(200, @target_id)

      dispatcher = start_dispatcher!(cursor: {0, 0, 0})

      assert_receive {:dispatched, [first, second], _place}

      assert {first.tx, first.op, first.type, first.entity_id} ==
               {201, :del_entity, Module2, @entity_id}

      assert {second.tx, second.entity_id} == {200, @target_id}

      settle(dispatcher)
    end

    test "hands over nothing when the round reads nothing" do
      dispatcher = start_dispatcher!(cursor: {0, 0, 0})

      wake(dispatcher)

      refute_receive {:dispatched, _effects, _place}, 100

      settle(dispatcher)
    end

    # A save running holds the limit back, and not the saves committing around it. The place stays
    # at the limit, so a client replaying from it gets them again.
    test "hands over the committed effects above the final limit, from the limit's place" do
      first = seed(200, @entity_id)
      {first_seq, _tx, _at} = first
      seed(201, @entity_id)

      read_edge = start_read_edge!()

      dispatcher =
        start_dispatcher!(
          advance: sandbox_advance(high: first_seq),
          cursor: {0, 0, 0},
          read_edge: read_edge
        )

      assert_receive {:dispatched, [%{tx: 200}, %{tx: 201}], {0, 0, 0}}

      wake(dispatcher)

      refute_receive {:dispatched, _effects, _place}, 100
      assert :sys.get_state(dispatcher).cursor == first
      assert ReadEdge.get(read_edge) == {first, Oplog.log_id()}

      settle(dispatcher)
    end

    test "hands over a save that commits into a seq it passed over, once" do
      first = seed(200, @entity_id)
      {first_seq, _tx, _at} = first
      skipped_seq = take_serial()
      seed(201, @entity_id)

      dispatcher = start_dispatcher!(advance: sandbox_advance(high: first_seq), cursor: {0, 0, 0})

      assert_receive {:dispatched, [%{tx: 200}, %{tx: 201}], {0, 0, 0}}

      seed(202, @entity_id, skipped_seq)
      wake(dispatcher)

      assert_receive {:dispatched, [%{tx: 202}], ^first}

      wake(dispatcher)

      refute_receive {:dispatched, _effects, _place}, 100

      settle(dispatcher)
    end

    # The rows read for a batch can hold a save that commits into a seq passed over after the batch
    # was read, or above the highest sent, and nothing else.
    test "hands over the highest seq sent and the ones below it it passed over" do
      first = seed(200, @entity_id)
      {first_seq, _tx, _at} = first
      skipped_seq = take_serial()
      {last_seq, _tx, _at} = seed(201, @entity_id)

      dispatcher = start_dispatcher!(advance: sandbox_advance(high: first_seq), cursor: {0, 0, 0})

      assert_receive {:sent, {^last_seq, [{^skipped_seq, ^skipped_seq}]}}

      seed(202, @entity_id, skipped_seq)
      wake(dispatcher)

      assert_receive {:sent, {^last_seq, []}}

      settle(dispatcher)
    end

    test "hands over each save that commits into the seqs it passed over, in turn" do
      first = seed(200, @entity_id)
      {first_seq, _tx, _at} = first
      first_skipped = take_serial()
      second_skipped = take_serial()
      seed(201, @entity_id)

      dispatcher = start_dispatcher!(advance: sandbox_advance(high: first_seq), cursor: {0, 0, 0})

      assert_receive {:dispatched, [%{tx: 200}, %{tx: 201}], {0, 0, 0}}

      seed(202, @entity_id, first_skipped)
      wake(dispatcher)

      assert_receive {:dispatched, [%{tx: 202}], ^first}

      seed(203, @entity_id, second_skipped)
      wake(dispatcher)

      assert_receive {:dispatched, [%{tx: 203}], ^first}

      settle(dispatcher)
    end

    # A commit is atomic, so a save with serials both among the ones passed over and above the
    # highest sent goes out whole.
    test "hands over a save with entries in a seq it passed over and above, together" do
      first = seed(200, @entity_id)
      {first_seq, _tx, _at} = first
      skipped_seq = take_serial()
      seed(201, @entity_id)

      dispatcher = start_dispatcher!(advance: sandbox_advance(high: first_seq), cursor: {0, 0, 0})

      assert_receive {:dispatched, [%{tx: 200}, %{tx: 201}], {0, 0, 0}}

      seed(202, @entity_id, skipped_seq)
      seed(202, @entity_id)
      wake(dispatcher)

      assert_receive {:dispatched, [%{seq: ^skipped_seq, tx: 202}, %{tx: 202}], ^first}

      settle(dispatcher)
    end

    test "hands over a save that commits into one of many seqs it passed over" do
      first = seed(200, @entity_id)
      {first_seq, _tx, _at} = first

      skipped_seqs =
        Enum.map(1..101, fn index ->
          skipped_seq = take_serial()
          seed(300 + index, @entity_id)

          skipped_seq
        end)

      dispatcher = start_dispatcher!(advance: sandbox_advance(high: first_seq), cursor: {0, 0, 0})

      assert_receive {:dispatched, effects, {0, 0, 0}}
      assert length(effects) == 102

      seed(202, @entity_id, Enum.at(skipped_seqs, 50))
      wake(dispatcher)

      assert_receive {:dispatched, [%{tx: 202}], ^first}

      wake(dispatcher)

      refute_receive {:dispatched, _effects, _place}, 100

      settle(dispatcher)
    end

    # Every save at or below the limit has ended, so a seq there it never read never will be.
    test "forgets a seq it passed over once the final limit passes it" do
      first = seed(200, @entity_id)
      {first_seq, _tx, _at} = first
      skipped_seq = take_serial()
      last = seed(201, @entity_id)
      {last_seq, _tx, _at} = last

      dispatcher = start_dispatcher!(advance: sandbox_advance(high: first_seq), cursor: {0, 0, 0})

      assert_receive {:dispatched, [%{tx: 200}, %{tx: 201}], {0, 0, 0}}
      assert :sys.get_state(dispatcher).unsent == [{skipped_seq, skipped_seq}]

      :sys.replace_state(dispatcher, &%{&1 | advance: sandbox_advance(high: last_seq)})
      wake(dispatcher)

      assert %{cursor: ^last, sent_through: ^last_seq, unsent: []} = :sys.get_state(dispatcher)
      refute_received {:dispatched, _effects, _place}

      settle(dispatcher)
    end

    # The numbers the rows carry are final up to the limit: every save at or below it has ended.
    test "hands over the final limit the round reached" do
      {first_seq, _tx, _at} = seed(200, @entity_id)
      seed(201, @entity_id)

      test_pid = self()

      handler = fn effects, _place, _sent, final_seq ->
        send(test_pid, {:final, effects, final_seq})
      end

      dispatcher =
        start_dispatcher!(
          advance: sandbox_advance(high: first_seq),
          cursor: {0, 0, 0},
          handler: handler
        )

      assert_receive {:final, [%{tx: 200}, %{tx: 201}], ^first_seq}

      settle(dispatcher)
    end

    # A save still running held the limit back below rows already handed over, and its end moves
    # the limit past them with nothing new to read - which the clients holding them are told.
    test "hands over a round that reads nothing when it moves the final limit" do
      {first_seq, _tx, _at} = seed(200, @entity_id)
      {last_seq, _tx, _at} = seed(201, @entity_id)

      dispatcher = start_dispatcher!(advance: sandbox_advance(high: first_seq), cursor: {0, 0, 0})

      assert_receive {:dispatched, [%{tx: 200}, %{tx: 201}], {0, 0, 0}}
      refute_received {:limit_moved, _final_seq}

      :sys.replace_state(dispatcher, &%{&1 | advance: sandbox_advance(high: last_seq)})
      wake(dispatcher)

      assert_receive {:limit_moved, ^last_seq}
      refute_received {:dispatched, _effects, _place}

      wake(dispatcher)

      refute_receive {:limit_moved, _final_seq}, 100

      settle(dispatcher)
    end

    # A limit below the place is a server that lost the commits above it, and the serials above
    # the limit go to other saves, whose effects reading on from the place would pass by.
    test "stops the sessions and begins again at a final limit below its place" do
      place = seed(200, @entity_id)
      {seq, tx, inserted_at} = place
      log_id = Oplog.log_id()

      dispatcher = start_dispatcher!(cursor: {seq + 5, tx, inserted_at})

      assert_receive :lost
      assert %{cursor: ^place, log_id: new_log_id} = :sys.get_state(dispatcher)
      assert new_log_id == Oplog.log_id()
      refute new_log_id == log_id

      settle(dispatcher)
    end

    test "stops the sessions and begins again at the next final limit when the limit loses its entry" do
      seed(200, @entity_id)

      {:ok, rounds} = Agent.start_link(fn -> 0 end)
      advance = sandbox_advance()

      losing_on_second = fn state ->
        advanced = advance.(state)

        case Agent.get_and_update(rounds, &{&1 + 1, &1 + 1}) do
          2 -> %{advanced | losses: advanced.losses + 1}
          _round -> advanced
        end
      end

      dispatcher = start_dispatcher!(advance: losing_on_second)
      :sys.get_state(dispatcher)
      refute_received :lost
      log_id = Oplog.log_id()

      place = seed(201, @entity_id)
      wake(dispatcher)

      assert_receive :lost
      refute_received {:dispatched, _effects, _place}
      assert :sys.get_state(dispatcher).cursor == place
      refute Oplog.log_id() == log_id

      settle(dispatcher)
    end

    test "stops the sessions and begins again at the next final limit when the server crashed" do
      seed(200, @entity_id)

      read_edge = start_read_edge!()
      dispatcher = start_dispatcher!(read_edge: read_edge)
      :sys.get_state(dispatcher)

      place = seed(201, @entity_id)
      :ok = crash_server()
      wake(dispatcher)

      assert_receive :lost
      refute_received {:dispatched, _effects, _place}
      assert :sys.get_state(dispatcher).cursor == place
      assert ReadEdge.get(read_edge) == {place, Oplog.log_id()}

      settle(dispatcher)
    end

    test "stops no session when the server only restarted" do
      seed(200, @entity_id)

      {:ok, rounds} = Agent.start_link(fn -> 0 end)
      advance = sandbox_advance()

      # A clean restart keeps the log id and moves the start time.
      restarted_on_second = fn state ->
        advanced = advance.(state)

        case Agent.get_and_update(rounds, &{&1 + 1, &1 + 1}) do
          2 -> %{advanced | run: Oplog.run_log_id(advanced.run) <> "/0"}
          _round -> advanced
        end
      end

      dispatcher = start_dispatcher!(advance: restarted_on_second)
      :sys.get_state(dispatcher)

      seed(201, @entity_id)
      wake(dispatcher)

      assert_receive {:dispatched, [%{tx: 201}], _place}
      refute_received :lost

      settle(dispatcher)
    end

    test "clears the read edge and moves the log id before it stops the sessions" do
      place = seed(200, @entity_id)
      {seq, tx, inserted_at} = place
      log_id = Oplog.log_id()
      read_edge = start_read_edge!()
      test_pid = self()

      dispatcher =
        start_dispatcher!(
          cursor: {seq + 5, tx, inserted_at},
          on_loss: fn -> send(test_pid, {:lost, ReadEdge.get(read_edge), Oplog.log_id()}) end,
          read_edge: read_edge
        )

      assert_receive {:lost, nil, new_log_id}
      refute new_log_id == log_id

      :sys.get_state(dispatcher)
      assert ReadEdge.get(read_edge) == {place, new_log_id}

      settle(dispatcher)
    end

    # The first round after a crash finds no run, and one can find the run moved while it reads:
    # either leaves the limit as it was, and the log may be of a run that lost what was sent.
    test "sends nothing in a round that couldn't date the log" do
      place = seed(200, @entity_id)
      seed(201, @entity_id)

      advance = sandbox_advance()
      uncounted = fn limit -> %{advance.(limit) | counted: false} end

      dispatcher = start_dispatcher!(advance: uncounted, cursor: place)

      :sys.get_state(dispatcher)

      refute_received {:dispatched, _effects, _place}
      assert :sys.get_state(dispatcher).cursor == place

      settle(dispatcher)
    end

    test "sends nothing in a round that found a loss and couldn't give the log a new id" do
      place = seed(200, @entity_id)
      {seq, tx, inserted_at} = place
      Enum.each(1..5, fn _index -> take_serial() end)
      seed(201, @entity_id)

      failing = fn _old_log_id -> raise DBConnection.ConnectionError, "the connection dropped" end

      dispatcher =
        start_dispatcher!(
          advance: sandbox_advance(high: seq),
          cursor: {seq + 5, tx, inserted_at},
          rotate_log_id: failing
        )

      assert is_binary(:sys.get_state(dispatcher).pending_rotation)
      refute_received {:dispatched, _effects, _place}

      settle(dispatcher)
    end

    test "stops the sessions once the log takes a new id, though the first try failed" do
      place = seed(200, @entity_id)
      {seq, tx, inserted_at} = place
      log_id = Oplog.log_id()
      read_edge = start_read_edge!()
      {:ok, tries} = Agent.start_link(fn -> 0 end)

      failing_once = fn old_log_id ->
        case Agent.get_and_update(tries, &{&1, &1 + 1}) do
          0 -> raise DBConnection.ConnectionError, "the connection dropped"
          _try -> Oplog.rotate_log_id(old_log_id)
        end
      end

      dispatcher =
        start_dispatcher!(
          cursor: {seq + 5, tx, inserted_at},
          read_edge: read_edge,
          rotate_log_id: failing_once
        )

      :sys.get_state(dispatcher)
      refute_received :lost
      assert ReadEdge.get(read_edge) == nil

      # Saves passing the place, which hide that the limit came out below it.
      last = Enum.reduce(201..206, nil, fn save_tx, _last -> seed(save_tx, @entity_id) end)
      wake(dispatcher)

      assert_receive :lost
      refute Oplog.log_id() == log_id

      :sys.get_state(dispatcher)
      assert ReadEdge.get(read_edge) == {last, Oplog.log_id()}

      settle(dispatcher)
    end

    test "stops no session while the limit keeps its entry" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!([])
      :sys.get_state(dispatcher)

      seed(201, @entity_id)
      wake(dispatcher)

      assert_receive {:dispatched, [%{tx: 201}], _place}
      refute_received :lost

      settle(dispatcher)
    end

    test "records how far it read, for whichever dispatcher replaces it" do
      seed(200, @entity_id)
      last = seed(201, @entity_id)

      read_edge = start_read_edge!()
      dispatcher = start_dispatcher!(cursor: {0, 0, 0}, read_edge: read_edge)

      assert_receive {:dispatched, [_first, _second], _place}

      # The delivery is not the barrier. The handler is what sends it, and the place moves once
      # that handler RETURNS - so a read taken on the delivery alone races the round recording it.
      # A synchronous call is answered only after the round is over.
      :sys.get_state(dispatcher)

      # Past the effects just handed over rather than back at their place, which is the difference
      # between a replacement carrying on and one repeating what the client already has.
      assert ReadEdge.get(read_edge) == {last, Oplog.log_id()}

      settle(dispatcher)
    end

    test "moves past what it handed over, so a second wake repeats nothing" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(cursor: {0, 0, 0})

      assert_receive {:dispatched, [%{tx: 200}], _place}

      wake(dispatcher)

      refute_receive {:dispatched, _effects, _place}, 100

      settle(dispatcher)
    end

    test "reads what was written since the last round" do
      dispatcher = start_dispatcher!([])
      start = :sys.get_state(dispatcher).cursor

      seed(200, @entity_id)
      wake(dispatcher)

      assert_receive {:dispatched, [%{tx: 200}], ^start}

      settle(dispatcher)
    end

    test "skips a round whose handler finds the data model under a hold, keeping its place" do
      seed(200, @entity_id)

      test_pid = self()
      {:ok, calls} = Agent.start_link(fn -> 0 end)

      handler = fn effects, place, _sent, _final_seq ->
        call = Agent.get_and_update(calls, &{&1 + 1, &1 + 1})
        send(test_pid, {:dispatched, call, effects, place})

        if call == 1, do: raise(Hologram.StaleModelError)
      end

      dispatcher = start_dispatcher!(cursor: {0, 0, 0}, handler: handler)

      assert_receive {:dispatched, 1, [%{tx: 200}], {0, 0, 0}}

      wake(dispatcher)
      assert_receive {:dispatched, 2, [%{tx: 200}], {0, 0, 0}}

      settle(dispatcher)
    end

    # A hot standby can't read the table naming the server's run, and a restore drops the system
    # tables for a while. Neither moves the log.
    test "keeps its place and its limit through a round that can't reach the database" do
      place = seed(200, @entity_id)

      test_pid = self()
      {:ok, rounds} = Agent.start_link(fn -> 0 end)
      advance = sandbox_advance()

      failing_after_first = fn state ->
        case Agent.get_and_update(rounds, &{&1 + 1, &1 + 1}) do
          1 ->
            advance.(state)

          round ->
            send(test_pid, {:round, round})
            raise DBConnection.ConnectionError, "the database went away"
        end
      end

      dispatcher = start_dispatcher!(advance: failing_after_first)
      limit = :sys.get_state(dispatcher).limit

      wake(dispatcher)
      assert_receive {:round, 2}

      state = :sys.get_state(dispatcher)

      assert state.cursor == place
      assert state.limit == limit

      settle(dispatcher)
    end

    # The database it would read is as likely out of reach, and a read raising every round would
    # take the dispatcher down.
    test "sends nothing in a round that can't work out the limit" do
      seed(200, @entity_id)

      test_pid = self()
      {:ok, rounds} = Agent.start_link(fn -> 0 end)
      advance = sandbox_advance()

      failing_after_first = fn state ->
        case Agent.get_and_update(rounds, &{&1 + 1, &1 + 1}) do
          1 ->
            advance.(state)

          round ->
            send(test_pid, {:round, round})
            raise DBConnection.ConnectionError, "the database went away"
        end
      end

      dispatcher = start_dispatcher!(advance: failing_after_first, cursor: {0, 0, 0})

      assert_receive {:dispatched, [%{tx: 200}], {0, 0, 0}}

      seed(201, @entity_id)
      wake(dispatcher)

      assert_receive {:round, 2}
      :sys.get_state(dispatcher)
      refute_received {:dispatched, _effects, _place}

      settle(dispatcher)
    end

    # Whether draining the mailbox happens before or after the log is read cannot be told
    # apart here: the sandbox runs the test inside one transaction, so nothing commits while the
    # dispatcher is working. The cluster scenario where transactions really commit while a
    # dispatcher is working is where the placement is proven.
    test "keeps reading after a wake that arrives with nothing behind it" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(cursor: {0, 0, 0})

      assert_receive {:dispatched, [%{tx: 200}], _place}

      wake(dispatcher)
      wake(dispatcher)

      assert Process.alive?(dispatcher)
      refute_receive {:dispatched, _effects, _place}, 100

      settle(dispatcher)
    end
  end

  # A save that rolls back or loses its connection announces nothing, so without a look of its own
  # a round waiting for one would wait for the poll.
  describe "handle :recheck" do
    test "looks again soon while a round waits for a save" do
      dispatcher = start_dispatcher!(advance: sandbox_advance(running: ["a"]))

      :erlang.trace(dispatcher, true, [:receive])

      assert_receive {:trace, ^dispatcher, :receive, :recheck}, @poll_timeout_ms
      assert_receive {:trace, ^dispatcher, :receive, :recheck}, @poll_timeout_ms

      settle(dispatcher)
    end

    test "doesn't look again when no round waits" do
      dispatcher = start_dispatcher!([])

      :erlang.trace(dispatcher, true, [:receive])

      refute_receive {:trace, ^dispatcher, :receive, :recheck}, 100

      settle(dispatcher)
    end

    test "keeps one look scheduled however many rounds run meanwhile" do
      dispatcher =
        start_dispatcher!(advance: sandbox_advance(running: ["a"]), recheck_interval_ms: 200)

      :erlang.trace(dispatcher, true, [:receive])

      wake(dispatcher)
      wake(dispatcher)

      assert_receive {:trace, ^dispatcher, :receive, :recheck}, @poll_timeout_ms
      refute_receive {:trace, ^dispatcher, :receive, :recheck}, 100

      settle(dispatcher)
    end
  end

  describe "prepared transactions" do
    test "warns when one holds the final limit back for over a minute" do
      dispatcher = start_dispatcher!(advance: sandbox_advance(running: ["-1/123"]))

      since = System.monotonic_time(:millisecond) - @prepared_warning_ms
      :sys.replace_state(dispatcher, &%{&1 | prepared_since: since})

      log =
        capture_log(fn ->
          wake(dispatcher)
          :sys.get_state(dispatcher)
        end)

      assert log =~ "a prepared transaction holding the serial lock has held back sync"

      settle(dispatcher)
    end

    test "warns once while the same stretch lasts" do
      dispatcher = start_dispatcher!(advance: sandbox_advance(running: ["-1/123"]))

      since = System.monotonic_time(:millisecond) - @prepared_warning_ms
      :sys.replace_state(dispatcher, &%{&1 | prepared_since: since})

      first_log =
        capture_log(fn ->
          wake(dispatcher)
          :sys.get_state(dispatcher)
        end)

      log =
        capture_log(fn ->
          wake(dispatcher)
          :sys.get_state(dispatcher)
        end)

      assert first_log =~ "prepared transaction"
      refute log =~ "prepared transaction"

      settle(dispatcher)
    end

    test "doesn't warn while it has held the limit back for less than a minute" do
      dispatcher = start_dispatcher!(advance: sandbox_advance(running: ["-1/123"]))

      log =
        capture_log(fn ->
          wake(dispatcher)
          :sys.get_state(dispatcher)
        end)

      refute log =~ "prepared transaction"

      settle(dispatcher)
    end

    test "doesn't count a save a session runs" do
      dispatcher = start_dispatcher!(advance: sandbox_advance(running: ["3/123"]))

      assert :sys.get_state(dispatcher).prepared_since == nil

      settle(dispatcher)
    end
  end

  describe "handle :notification" do
    test "listens for appends on the channel they announce themselves on" do
      {:ok, notifications} = start_supervised({NotificationsStub, reply_to: self()})

      dispatcher = start_dispatcher!(notifications: notifications)

      assert_receive {:listening, channel}
      assert channel == Oplog.channel()

      settle(dispatcher)
    end

    # A connection that opens after booting has not opened yet when the dispatcher starts, so this
    # is the answer it gets on a cold node - and refusing it would fail the dispatcher for the one
    # reason the connection is allowed to open late.
    test "takes the channel that will be listened on once the connection opens" do
      {:ok, notifications} =
        start_supervised({NotificationsStub, answer: :eventually, reply_to: self()})

      dispatcher = start_dispatcher!(notifications: notifications)

      assert_receive {:listening, _channel}

      # Asked for its state rather than checked for a pulse: the listen happens in the continue,
      # which runs after start_link returns, so a refusal of that answer kills the process a moment
      # later. A call queues behind the continue and answers only if it got through.
      assert {_seq, _tx, _at} = :sys.get_state(dispatcher).cursor

      settle(dispatcher)
    end

    test "reads the log when an append announces itself" do
      dispatcher = start_dispatcher!([])
      :sys.get_state(dispatcher)

      seed(200, @entity_id)
      send(dispatcher, {:notification, self(), make_ref(), Oplog.channel(), ""})

      assert_receive {:dispatched, [%{tx: 200}], _place}

      settle(dispatcher)
    end
  end

  describe "handle :poll" do
    test "reads the log again after the poll interval, without being told to" do
      dispatcher = start_dispatcher!(poll_interval_ms: @armed_poll_interval_ms)
      :sys.get_state(dispatcher)

      seed(200, @entity_id)

      assert_receive {:dispatched, [%{tx: 200}], _place}, @poll_timeout_ms

      settle(dispatcher)
    end

    # A round over an unchanged log hands nothing over, so the polls after the first are
    # invisible from the outside - tracing what the dispatcher receives is what tells a timer
    # that rescheduled itself apart from one that fired once and stopped.
    test "keeps polling" do
      dispatcher = start_dispatcher!([])

      :erlang.trace(dispatcher, true, [:receive])

      # The poll handed over by hand is the one that arms a timer - anything after it came from
      # that timer, and could only have come from the handler arming another.
      arm_polling(dispatcher)
      assert_receive {:trace, ^dispatcher, :receive, :poll}, @poll_timeout_ms
      assert_receive {:trace, ^dispatcher, :receive, :poll}, @poll_timeout_ms

      settle(dispatcher)
    end
  end
end
