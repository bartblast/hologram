defmodule Hologram.Mutation.RecordTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Mutation.Record

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Entity

  @client_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"
  @other_client_id "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e10"

  defp claim(client_id, seq, actor_id \\ nil, model_hash \\ "h") do
    Connection.transaction(fn -> claim!(client_id, seq, actor_id, model_hash) end)
  end

  defp rows do
    statement = """
    SELECT "client_id", "seq", "actor_id", "model_hash", "result", "envelope", "answered_at"
    FROM "hologram_system"."mutation"
    ORDER BY "client_id", "seq"
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [client_id, seq, actor_id, model_hash, result, envelope, answered_at] ->
      %{
        actor_id: Codec.decode(actor_id, :uuid),
        answered_at: answered_at,
        client_id: client_id,
        envelope: envelope,
        model_hash: model_hash,
        result: result,
        seq: seq
      }
    end)
  end

  describe "claim!/4" do
    test "claims the record for a batch, with no answer yet" do
      assert claim(@client_id, 1) == {:ok, :ok}

      assert [row] = rows()
      assert %{actor_id: nil, client_id: @client_id, model_hash: "h", result: nil, seq: 1} = row
      assert row.envelope == nil
      assert %DateTime{} = row.answered_at
    end

    test "records the user who sent the batch" do
      user_id = Entity.generate_id()

      claim(@client_id, 1, user_id)

      assert [%{actor_id: ^user_id}] = rows()
    end

    test "claims each sequence number of one client on its own" do
      claim(@client_id, 1)
      claim(@client_id, 2)

      assert Enum.map(rows(), & &1.seq) == [1, 2]
    end

    test "claims one sequence number for each client on its own" do
      claim(@client_id, 1)
      claim(@other_client_id, 1)

      assert Enum.map(rows(), & &1.client_id) == [@client_id, @other_client_id]
    end

    test "rolls the transaction back with :duplicate when the batch is already recorded" do
      claim(@client_id, 1)

      assert claim(@client_id, 1) == {:error, :duplicate}

      assert length(rows()) == 1
    end
  end

  describe "complete!/3" do
    test "records the answer the batch got" do
      claim(@client_id, 1)

      assert complete!(@client_id, 1, %{"status" => "confirmed", "dropped" => %{}}) == :ok

      assert [%{result: %{"status" => "confirmed", "dropped" => %{}}}] = rows()
    end

    test "answers only the batch it names" do
      claim(@client_id, 1)
      claim(@client_id, 2)

      complete!(@client_id, 2, %{"status" => "confirmed"})

      assert Enum.map(rows(), & &1.result) == [nil, %{"status" => "confirmed"}]
    end
  end

  describe "find/2" do
    test "returns the sender and the answer the batch got" do
      user_id = Entity.generate_id()

      claim(@client_id, 1, user_id)
      complete!(@client_id, 1, %{"status" => "confirmed"})

      assert find(@client_id, 1) == %{
               actor_id: user_id,
               result: %{"status" => "confirmed"}
             }
    end

    test "returns nil for a batch with no record" do
      assert find(@client_id, 1) == nil
    end

    test "returns no answer for a batch claimed but not answered" do
      claim(@client_id, 1)

      assert find(@client_id, 1) == %{actor_id: nil, result: nil}
    end

    test "returns nothing of another batch's record" do
      claim(@client_id, 1)
      complete!(@client_id, 1, %{"status" => "confirmed"})

      assert find(@client_id, 2) == nil
      assert find(@other_client_id, 1) == nil
    end
  end
end
