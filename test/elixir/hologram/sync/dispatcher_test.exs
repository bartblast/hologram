defmodule Hologram.Sync.DispatcherTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Sync.Dispatcher

  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Outbox
  alias Hologram.Sync.Dispatcher
  alias Hologram.Sync.Place
  alias Hologram.Test.Fixtures.Entity.Module2

  @entity_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"

  # Wide enough that the sandbox allowance always lands before the first poll: a dispatcher that
  # reads before being let in checks out its own connection, and a failed read takes the process
  # down with the timer that would have proven it reschedules.
  @poll_interval_ms 300

  @poll_timeout_ms 2_000

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

  defp start_place!(remembering \\ nil) do
    place = start_supervised!(Place)

    if remembering, do: :ok = Place.put(place, remembering)

    place
  end

  # Stands in for a Postgrex.Notifications process, which answers listen/2 with a reference and
  # would otherwise need a connection of its own.
  defmodule NotificationsStub do
    @moduledoc false

    use GenServer

    @spec start_link(keyword) :: GenServer.on_start()
    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl GenServer
    def init(opts), do: {:ok, opts[:reply_to]}

    @impl GenServer
    def handle_call({{:listen, channel}, _caller}, _from, reply_to) do
      send(reply_to, {:listening, channel})

      {:reply, {:ok, make_ref()}, reply_to}
    end
  end

  describe "start_link/1" do
    test "starts reading at the log's current edge when given no cursor" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!([])

      wake(dispatcher)

      refute_receive {:dispatched, _transactions, _place}, 100
    end

    # What a dispatcher replacing a crashed one has to do: the state of the one that died is gone,
    # and starting at the edge would skip the window it was reading - which the sessions that
    # outlived it would then be carried past, holding a place covering rows they were never sent.
    test "resumes from where the dispatcher it replaces got to" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(place: start_place!(200))

      wake(dispatcher)

      assert_receive {:dispatched, [{200, _events}], {200, 0}}
    end

    test "starts at the edge when the holder remembers nothing" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(place: start_place!())

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

      place = start_place!()
      dispatcher = start_dispatcher!(cursor: 200, place: place)

      wake(dispatcher)
      assert_receive {:dispatched, [{200, _events}], _place}

      recorded = Place.get(place)

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
      place = start_place!()
      dispatcher = start_dispatcher!(cursor: 200, place: place)

      wake(dispatcher)
      refute_receive {:dispatched, _transactions, _place}, 100

      recorded = Place.get(place)

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

    test "reads the log when an append announces itself" do
      seed(200, @entity_id)

      dispatcher = start_dispatcher!(cursor: 200)

      send(dispatcher, {:notification, self(), make_ref(), Outbox.channel(), ""})

      assert_receive {:dispatched, [{200, _events}], _place}
    end
  end

  # A dispatcher left polling into the teardown queries the sandbox connection while its owner is
  # rolling back and checking in, which kills the owner - so these stop it before they finish.
  describe "handle :poll" do
    test "reads the log again after the poll interval, without being told to" do
      seed(200, @entity_id)

      start_dispatcher!(cursor: 200, poll_interval_ms: @poll_interval_ms)

      assert_receive {:dispatched, [{200, _events}], _place}, @poll_timeout_ms

      stop_supervised!(Dispatcher)
    end

    # A round over an unchanged log hands nothing over, so the polls after the first are
    # invisible from the outside - tracing what the dispatcher receives is what tells a timer
    # that rescheduled itself apart from one that fired once and stopped.
    test "keeps polling" do
      dispatcher = start_dispatcher!(cursor: 200, poll_interval_ms: @poll_interval_ms)

      :erlang.trace(dispatcher, true, [:receive])

      # The first poll is the one start_link armed - a second can only come from the first having
      # armed another.
      assert_receive {:trace, ^dispatcher, :receive, :poll}, @poll_timeout_ms
      assert_receive {:trace, ^dispatcher, :receive, :poll}, @poll_timeout_ms

      stop_supervised!(Dispatcher)
    end
  end
end
