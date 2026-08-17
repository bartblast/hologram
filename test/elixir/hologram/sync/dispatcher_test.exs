defmodule Hologram.Sync.DispatcherTest do
  # Grouped with Hologram.Sync.ReadEdgeTest - see the reasoning there. Both start a read edge under
  # the one name it registers under, so they must not run at the same time.
  use Hologram.Test.DatabaseCase, async: true, group: :sync_read_edge

  import Hologram.Sync.Dispatcher

  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Outbox
  alias Hologram.Sync.Dispatcher
  alias Hologram.Sync.ReadEdge
  alias Hologram.Test.Fixtures.Entity.Module2

  @entity_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"

  # Wide enough that the sandbox allowance always lands before the first poll. A dispatcher that
  # reads before being let in reads through a connection of its own, where this test's uncommitted
  # row does not exist - and having read, it moves past the place that row sits at, so no later
  # round finds it either. Only the test whose FIRST round has to find something needs this.
  @poll_interval_ms 300

  # For the test that only has to see the timer re-arm itself: nothing has to be found, so the
  # interval is brought in close and the first poll handed over once everything is set up.
  @armed_poll_interval_ms 20

  @poll_timeout_ms 2_000

  # Brings the poll interval within reach and hands over the first poll, whose handler is what arms
  # a timer at the new interval. Done after the sandbox has let the dispatcher in, so that no round
  # runs before it is allowed to read.
  defp arm_polling(dispatcher) do
    :sys.replace_state(dispatcher, &%{&1 | poll_interval_ms: @armed_poll_interval_ms})

    send(dispatcher, :poll)
  end

  defp seed(tx, entity_id) do
    statement = """
    INSERT INTO "hologram_system"."outbox" ("op", "type", "entity_id", "tx", "model_hash")
    VALUES ('del_entity', 'Hologram.Test.Fixtures.Entity.Module2', $1, $2, 'seeded')
    """

    {:ok, _result} = Connection.query(statement, [Codec.encode(entity_id, :uuid), tx])

    :ok
  end

  # The dispatcher reads from its own process, which the sandbox owner must let in - otherwise it
  # would reach the pool rather than the transaction this test is writing into. The result is not
  # asserted: a dispatcher polling on a short interval can read once before the allowance lands,
  # which checks a connection out for itself and answers {:already, :owner}. The tests that care
  # say so by what they read - a dispatcher on the wrong connection finds none of these rows.
  # Stops the polling and waits for whatever round is running to finish: a dispatcher taken down
  # mid-read takes the sandbox connection with it, and the owner has a rollback left to do on it.
  defp settle(dispatcher) do
    :sys.replace_state(dispatcher, &%{&1 | poll_interval_ms: :timer.minutes(1)})
    :ok = :sys.suspend(dispatcher)

    stop_supervised!(Dispatcher)
  end

  defp start_dispatcher!(opts) do
    test_pid = self()
    handler = fn transactions, place -> send(test_pid, {:dispatched, transactions, place}) end

    opts =
      opts
      |> Keyword.put_new(:handler, handler)
      |> Keyword.put_new(:poll_interval_ms, :timer.minutes(1))

    pid = start_supervised!({Dispatcher, opts})

    DBConnection.Ownership.ownership_allow(DB.pool_name(), self(), pid, [])

    pid
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
    test "starts reading at the log's current edge when given no cursor" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!([])

      wake(dispatcher)

      refute_receive {:dispatched, _transactions, _place}, 100
    end

    # The place is taken when the dispatcher starts, not when something first wakes it - and what
    # usually wakes it is the very append a client is waiting for. Read then, the edge would already
    # be above that append and the window opened over it would be empty, passing it by for good.
    test "takes the log's edge as its place at start, rather than at its first round" do
      dispatcher = start_dispatcher!([])

      assert is_integer(:sys.get_state(dispatcher).cursor)
    end

    # What a dispatcher replacing a crashed one has to do: the state of the one that died is gone,
    # and starting at the edge would skip the window it was reading - which the sessions that
    # outlived it would then be carried past, holding a place covering rows they were never sent.
    test "resumes from where the dispatcher it replaces got to" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(read_edge: start_read_edge!(200))

      wake(dispatcher)

      assert_receive {:dispatched, [{200, _events}], {200, 0}}
    end

    test "starts at the edge when nothing was recorded to resume from" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(read_edge: start_read_edge!())

      wake(dispatcher)

      refute_receive {:dispatched, _transactions, _place}, 100
    end

    test "refuses to start with nowhere to send what it reads" do
      assert_raise KeyError, fn -> init([]) end
    end
  end

  describe "handle :wake" do
    # The place is what a frame built from this batch may claim a client has reached: replaying
    # from it re-reads the whole batch, and never less.
    test "hands over the place the window was read from" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(cursor: 200)

      wake(dispatcher)

      assert_receive {:dispatched, _transactions, {200, 0}}
    end

    test "hands over the transactions the window holds" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(cursor: 200)

      wake(dispatcher)

      assert_receive {:dispatched, [{200, [event]}], _place}
      assert event.op == :del_entity
      assert event.type == Module2
      assert event.entity_id == @entity_id
    end

    test "hands over nothing when the window is empty" do
      dispatcher = start_dispatcher!(cursor: 200)

      wake(dispatcher)

      refute_receive {:dispatched, _transactions, _place}, 100
    end

    test "records how far it read, for whichever dispatcher replaces it" do
      seed(200, @entity_id)

      read_edge = start_read_edge!()
      dispatcher = start_dispatcher!(cursor: 200, read_edge: read_edge)

      wake(dispatcher)
      assert_receive {:dispatched, [{200, _events}], _place}

      recorded = ReadEdge.get(read_edge)

      # Asserted as a number before being compared: nothing recorded leaves nil, which every
      # integer sorts below rather than failing against.
      assert is_integer(recorded)

      # Past the window just handed over rather than back at its start, which is the difference
      # between a replacement carrying on and one repeating what the client already has.
      assert recorded > 200
    end

    # The empty round moves the place too, and has to: a node quiet for an hour would otherwise
    # leave its replacement rereading an hour of log that nothing was waiting for.
    test "records how far it read even when the window held nothing" do
      read_edge = start_read_edge!()
      dispatcher = start_dispatcher!(cursor: 200, read_edge: read_edge)

      wake(dispatcher)
      refute_receive {:dispatched, _transactions, _place}, 100

      recorded = ReadEdge.get(read_edge)

      assert is_integer(recorded)
      assert recorded > 200
    end

    test "moves past what it handed over, so a second wake repeats nothing" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(cursor: 200)

      wake(dispatcher)
      assert_receive {:dispatched, [{200, _events}], _place}

      wake(dispatcher)

      refute_receive {:dispatched, _transactions, _place}, 100
    end

    # Whether draining the mailbox happens before or after the window is read cannot be told
    # apart here: the sandbox runs the test inside one transaction, so the dispatcher's edge
    # never reaches the rows this test writes, and every round after the first reads nothing
    # whichever way it drains. The cluster scenario where transactions really commit while a
    # dispatcher is working is where the placement is proven.
    test "keeps reading after a wake that arrives with nothing behind it" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(cursor: 200)

      wake(dispatcher)
      assert_receive {:dispatched, [{200, _events}], _place}

      wake(dispatcher)
      wake(dispatcher)

      assert Process.alive?(dispatcher)
      refute_receive {:dispatched, _transactions, _place}, 100
    end
  end

  describe "handle :notification" do
    test "listens for appends on the channel they announce themselves on" do
      {:ok, notifications} = start_supervised({NotificationsStub, reply_to: self()})

      start_dispatcher!(notifications: notifications)

      assert_receive {:listening, channel}
      assert channel == Outbox.channel()
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
      assert is_integer(:sys.get_state(dispatcher).cursor)
    end

    test "reads the log when an append announces itself" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(cursor: 200)

      send(dispatcher, {:notification, self(), make_ref(), Outbox.channel(), ""})

      assert_receive {:dispatched, [{200, _events}], _place}
    end
  end

  # These start with the timer an interval away that nothing reaches - a minute - and bring it in
  # once they are set up, by handing the dispatcher a poll themselves. What that buys is that no
  # round runs while the sandbox is still letting the dispatcher in, and none is left running
  # while the owner rolls back: a dispatcher reading the sandbox connection around either edge
  # takes the connection, and with it the test's ability to end cleanly.
  describe "handle :poll" do
    test "reads the log again after the poll interval, without being told to" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(cursor: 200, poll_interval_ms: @poll_interval_ms)

      assert_receive {:dispatched, [{200, _events}], _place}, @poll_timeout_ms

      settle(dispatcher)
    end

    # A round over an unchanged log hands nothing over, so the polls after the first are
    # invisible from the outside - tracing what the dispatcher receives is what tells a timer
    # that rescheduled itself apart from one that fired once and stopped.
    test "keeps polling" do
      dispatcher = start_dispatcher!(cursor: 200)

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
