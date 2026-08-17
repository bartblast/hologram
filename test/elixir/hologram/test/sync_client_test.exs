defmodule Hologram.Test.SyncClientTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Test.SyncClient

  alias Hologram.Entity.Model
  alias Hologram.Sync.Frame
  alias Hologram.Test.SyncClient

  defp client_holding(frames) do
    %SyncClient{frames: frames, request_id: make_ref()}
  end

  defp frame(event_name) do
    %{"data" => "{}", "event" => event_name, "id" => "1"}
  end

  describe "await_frame/3" do
    test "hands over a frame the client has already read" do
      client = client_holding([frame("synced"), frame("sync_deltas")])

      assert {%{"event" => "sync_deltas"}, _client} = await_frame(client, "sync_deltas", 0)
    end

    test "raises rather than letting a test wait on a frame that never comes" do
      client = client_holding([])

      assert_raise RuntimeError, ~s(no "sync_deltas" frame arrived within the timeout), fn ->
        await_frame(client, "sync_deltas", 0)
      end
    end
  end

  describe "greeting_params/1" do
    test "claims what is true of this build unless told otherwise" do
      assert greeting_params(page: "MyApp.BoardPage") == [
               model_hash: Model.hash(),
               page: "MyApp.BoardPage",
               protocol_version: Frame.protocol_version()
             ]
    end

    test "speaks as a stale client when told to" do
      params = greeting_params(page: "MyApp.BoardPage", model_hash: "a3f9c2")

      assert params[:model_hash] == "a3f9c2"
    end

    test "speaks another wire format when told to" do
      params = greeting_params(page: "MyApp.BoardPage", protocol_version: 99)

      assert params[:protocol_version] == 99
    end

    test "hands a returning client's place back" do
      params = greeting_params(page: "MyApp.BoardPage", cursor: "g8uxAAAAZQ")

      assert params[:cursor] == "g8uxAAAAZQ"
    end

    test "names no place on a first visit" do
      params = greeting_params(page: "MyApp.BoardPage")

      refute Keyword.has_key?(params, :cursor)
    end
  end

  describe "next_frame/3" do
    test "hands over the next frame of the kind asked for" do
      client = client_holding([frame("sync_deltas")])

      assert {:ok, %{"event" => "sync_deltas"}, _client} = next_frame(client, "sync_deltas", 0)
    end

    test "passes over the frames of other kinds on the way to it" do
      client = client_holding([frame("synced"), frame("sync_resync"), frame("sync_deltas")])

      assert {:ok, %{"event" => "sync_deltas"}, _client} = next_frame(client, "sync_deltas", 0)
    end

    # Nothing arriving is an answer here rather than a failure, which is how a test says a SECOND
    # frame never came.
    test "says so when nothing of the kind is already read" do
      client = client_holding([frame("synced")])

      assert {:timeout, _client} = next_frame(client, "sync_deltas", 0)
    end

    # A real timeout rather than an expired deadline: this waits on the socket and gives up, which
    # is the path a test counting frames actually takes.
    test "says so after waiting for one that never arrives" do
      client = client_holding([])

      assert {:timeout, _client} = next_frame(client, "sync_deltas", 20)
    end

    test "leaves the frames it did not hand over behind it" do
      client = client_holding([frame("sync_deltas"), frame("synced")])

      assert {:ok, _frame, remaining} = next_frame(client, "sync_deltas", 0)
      assert {:ok, %{"event" => "synced"}, _client} = next_frame(remaining, "synced", 0)
    end

    # Handing one over has to CONSUME it, or a test counting frames would see the same one twice
    # and call a single delivery a double.
    test "does not hand the same frame over twice" do
      client = client_holding([frame("sync_deltas")])

      assert {:ok, _frame, remaining} = next_frame(client, "sync_deltas", 0)
      assert {:timeout, _client} = next_frame(remaining, "sync_deltas", 0)
    end
  end

  describe "parse_frames/1" do
    test "reads a complete frame into its fields" do
      buffer = "event: synced\nid: 42\ndata: Type.map([])\n\n"

      assert parse_frames(buffer) ==
               {[%{"event" => "synced", "id" => "42", "data" => "Type.map([])"}], ""}
    end

    test "reads every complete frame the buffer holds, in arrival order" do
      buffer = "event: sync_deltas\nid: 1\ndata: a\n\nevent: synced\nid: 2\ndata: b\n\n"

      assert {[first, second], ""} = parse_frames(buffer)
      assert first["event"] == "sync_deltas"
      assert second["event"] == "synced"
    end

    test "keeps a frame the wire has split rather than dropping it" do
      assert parse_frames("event: synced\nid: 4") == {[], "event: synced\nid: 4"}
    end

    test "keeps the partial tail while reading the complete frames before it" do
      buffer = "event: synced\nid: 1\ndata: a\n\nevent: sync_del"

      assert parse_frames(buffer) ==
               {[%{"event" => "synced", "id" => "1", "data" => "a"}], "event: sync_del"}
    end

    test "keeps a data value holding the field separator whole" do
      buffer = "event: synced\ndata: Type.bitstring(\"a: b\")\n\n"

      assert {[frame], ""} = parse_frames(buffer)
      assert frame["data"] == ~s|Type.bitstring("a: b")|
    end

    test "reads nothing from an empty buffer" do
      assert parse_frames("") == {[], ""}
    end
  end
end
