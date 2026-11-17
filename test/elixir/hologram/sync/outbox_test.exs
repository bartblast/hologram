defmodule Hologram.Sync.OutboxTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Sync.Outbox

  alias Hologram.Sync.Frame
  alias Hologram.Test.Fixtures.Entity.Module2

  @cursor "g8uxAAAAZQ"

  # The id is the one part of a chunk the outbox picks, so the chunk is compared with what the
  # frame encodes under the id it was given.
  defp event_id("event: " <> _rest = chunk) do
    [_event, "id: " <> id | _rest] = String.split(chunk, "\n")

    String.to_integer(id)
  end

  describe "put/2" do
    test "sends a deltas message as the chunk the frame encodes, beside the session sending it" do
      deltas = [Frame.unsync_entity("abc", Module2)]

      :ok =
        self()
        |> new([])
        |> put({:sync_deltas, @cursor, deltas, 7})

      session = self()
      assert_receive {:sync_frame, ^session, chunk}

      id = event_id(chunk)
      assert chunk == Frame.encode_deltas_envelope(id, @cursor, deltas, 7)
    end

    test "sends a synced message as the chunk the frame encodes, beside the session sending it" do
      :ok =
        self()
        |> new([])
        |> put({:sync_synced, {:types, [Module2]}, nil})

      session = self()
      assert_receive {:sync_frame, ^session, chunk}

      id = event_id(chunk)
      assert chunk == Frame.encode_synced_envelope(id, {:types, [Module2]}, nil)
    end

    test "sends the message as the term it is when raw" do
      :ok =
        self()
        |> new(raw: true)
        |> put({:sync_synced, :all, @cursor})

      assert_receive {:sync_synced, :all, @cursor}
    end
  end
end
