defmodule Hologram.Sync.FrameTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.Frame

  alias Hologram.Compiler.Encoder
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2

  @cursor "g8uxAAAAZQ"

  defp put_entity(row) do
    %{data: row, id: row.id, op: :put_entity, type: "Hologram.Test.Fixtures.Entity.Module2"}
  end

  describe "encode_deltas_envelope/3" do
    test "wraps the deltas in a sync_deltas SSE event envelope" do
      row = Entity.new(Module2, a: true, c: "first")
      deltas = [put_entity(row)]

      payload = %{
        cursor: @cursor,
        deltas: deltas,
        model_hash: Model.hash(),
        protocol_version: 1
      }

      encoded = Encoder.encode_client_term!(payload)

      assert encode_deltas_envelope(42, @cursor, deltas) ==
               "event: sync_deltas\nid: 42\ndata: #{encoded}\n\n"
    end

    test "stamps the model the values were read under" do
      envelope = encode_deltas_envelope(42, @cursor, [])

      assert String.contains?(envelope, Model.hash())
    end

    test "stamps the protocol version the frame is spelled in" do
      envelope = encode_deltas_envelope(42, @cursor, [])

      assert String.contains?(envelope, ~s[Type.atom("protocol_version")])
      assert String.contains?(envelope, "Type.integer(#{protocol_version()}n)")
    end

    test "carries the cursor the client hands back" do
      envelope = encode_deltas_envelope(42, @cursor, [])

      assert String.contains?(envelope, ~s[Type.bitstring("#{@cursor}")])
    end

    test "carries no cursor when there is nowhere to resume from" do
      envelope = encode_deltas_envelope(42, nil, [])

      assert String.contains?(envelope, ~s[Type.atom("nil")])
    end

    test "never carries the value of a server-only attribute" do
      row = Entity.new(Module14, email: "user@test.com", password_hash: "hashed_secret_v3")

      delta = %{
        data: row,
        id: row.id,
        op: :put_entity,
        type: "Hologram.Test.Fixtures.Entity.Module14"
      }

      envelope = encode_deltas_envelope(42, @cursor, [delta])

      assert String.contains?(envelope, ~s[Type.bitstring("user@test.com")])
      refute String.contains?(envelope, "hashed_secret_v3")
    end
  end

  describe "encode_synced_envelope/1" do
    test "wraps the completeness marker in a synced SSE event envelope" do
      payload = %{protocol_version: 1}
      encoded = Encoder.encode_client_term!(payload)

      assert encode_synced_envelope(42) == "event: synced\nid: 42\ndata: #{encoded}\n\n"
    end
  end

  describe "protocol_version/0" do
    test "returns the version this build speaks" do
      assert protocol_version() == 1
    end
  end
end
