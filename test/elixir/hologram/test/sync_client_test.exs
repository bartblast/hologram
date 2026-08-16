defmodule Hologram.Test.SyncClientTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Test.SyncClient

  alias Hologram.Entity.Model
  alias Hologram.Sync.Frame

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
