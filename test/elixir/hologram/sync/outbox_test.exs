defmodule Hologram.Sync.OutboxTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.Outbox

  alias Hologram.Sync.Frame
  alias Hologram.Test.Fixtures.Entity.Module2

  @cursor "g8uxAAAAZQ"
  @marker {:sync_synced, :all, nil}

  # The id is the one part of a chunk the outbox picks, so the chunk is compared with what the
  # frame encodes under the id it was given.
  defp event_id("event: " <> _rest = chunk) do
    [_event, "id: " <> id | _rest] = String.split(chunk, "\n")

    String.to_integer(id)
  end

  # Waits until the :DOWN of the given monitor is in this process's mailbox, without taking it.
  defp await_queued_down(ref) do
    {:messages, messages} = Process.info(self(), :messages)

    unless Enum.any?(messages, &match?({:DOWN, ^ref, :process, _pid, _reason}, &1)) do
      Process.sleep(1)
      await_queued_down(ref)
    end
  end

  # Runs the given function once the given process is blocked in a receive, so what it sends reaches
  # a wait rather than the mailbox before it. Taking answers already waiting never blocks, so only
  # the wait for room shows the process waiting. A process never seen waiting is sent nothing, and
  # the wait it never reached times out, failing the test rather than passing it the other way.
  defp when_waiting(pid, fun) do
    spawn(fn ->
      if await_waiting(pid, 1_000) == :ok, do: fun.()
    end)
  end

  defp await_waiting(_pid, 0), do: :timeout

  defp await_waiting(pid, tries) do
    if Process.info(pid, :status) == {:status, :waiting} do
      :ok
    else
      Process.sleep(1)
      await_waiting(pid, tries - 1)
    end
  end

  describe "put/2" do
    test "sends a deltas message as the chunk the frame encodes, beside the session sending it" do
      deltas = [Frame.unsync_entity("abc", Module2)]

      {:ok, _outbox} =
        self()
        |> new([])
        |> put({:sync_deltas, @cursor, deltas, 7})

      session = self()
      assert_receive {:sync_frame, ^session, chunk}

      id = event_id(chunk)
      assert chunk == Frame.encode_deltas_envelope(id, @cursor, deltas, 7)
    end

    test "sends a synced message as the chunk the frame encodes, beside the session sending it" do
      {:ok, _outbox} =
        self()
        |> new([])
        |> put({:sync_synced, {:types, [Module2]}, nil})

      session = self()
      assert_receive {:sync_frame, ^session, chunk}

      id = event_id(chunk)
      assert chunk == Frame.encode_synced_envelope(id, {:types, [Module2]}, nil)
    end

    test "sends the message as the term it is when raw" do
      {:ok, _outbox} =
        self()
        |> new(raw: true)
        |> put({:sync_synced, :all, @cursor})

      assert_receive {:sync_synced, :all, @cursor}
    end

    test "sends as many as it may without an answer" do
      outbox = new(self(), max_unwritten: 2, stall_ms: 0)

      assert {:ok, once} = put(outbox, @marker)
      assert {:ok, twice} = put(once, @marker)

      assert twice.unwritten == 2
      assert_received {:sync_frame, _session, _first}
      assert_received {:sync_frame, _session, _second}
    end

    test "waits for an answer before sending past as many as it may" do
      session = self()
      {:ok, outbox} = put(new(session, max_unwritten: 1, stall_ms: 1_000), @marker)
      assert_received {:sync_frame, ^session, _first}

      when_waiting(session, fn -> send(session, :sync_written) end)

      assert {:ok, waited} = put(outbox, @marker)

      assert waited.unwritten == 1
      assert_received {:sync_frame, ^session, _second}
    end

    test "takes the answers already waiting before it counts" do
      {:ok, outbox} = put(new(self(), max_unwritten: 1, stall_ms: 0), @marker)

      send(self(), :sync_written)

      assert {:ok, answered} = put(outbox, @marker)
      assert answered.unwritten == 1
    end

    test "gives up on a client that answers nothing for as long as it may wait" do
      {:ok, outbox} = put(new(self(), max_unwritten: 1, stall_ms: 50), @marker)
      assert_received {:sync_frame, _session, _first}

      assert put(outbox, @marker) == :stalled
      refute_received {:sync_frame, _session, _second}
    end

    test "stops while it waits, when the stream asks the session to" do
      session = self()
      {:ok, outbox} = put(new(session, max_unwritten: 1, stall_ms: 1_000), @marker)
      assert_received {:sync_frame, ^session, _first}

      when_waiting(session, fn -> send(session, :sync_stop) end)

      assert put(outbox, @marker) == :stopped
      refute_received {:sync_frame, ^session, _second}
    end

    test "stops when the stream asked the session to before it was sent" do
      send(self(), :sync_stop)

      assert put(new(self(), []), @marker) == :stopped
      refute_received {:sync_frame, _session, _chunk}
    end

    test "stops while it waits, when the client goes" do
      session = self()
      client = spawn(fn -> receive(do: (:go -> :ok)) end)
      {:ok, outbox} = put(new(client, max_unwritten: 1, stall_ms: 1_000), @marker)

      when_waiting(session, fn -> send(client, :go) end)

      assert put(outbox, @marker) == :stopped
    end

    test "stops when the client went before it was sent" do
      client = spawn(fn -> receive(do: (:go -> :ok)) end)
      outbox = new(client, [])

      send(client, :go)
      await_queued_down(outbox.client_ref)

      assert put(outbox, @marker) == :stopped
    end

    test "never waits when raw" do
      outbox = new(self(), max_unwritten: 1, raw: true, stall_ms: 0)

      assert {:ok, once} = put(outbox, @marker)
      assert {:ok, _twice} = put(once, @marker)

      assert_received @marker
      assert_received @marker
    end
  end

  describe "written/1" do
    test "frees room for one more chunk" do
      {:ok, outbox} = put(new(self(), max_unwritten: 1, stall_ms: 0), @marker)

      assert {:ok, _sent} =
               outbox
               |> written()
               |> put(@marker)
    end
  end
end
