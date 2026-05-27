defmodule Hologram.Realtime.ReceiptTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Realtime.Receipt

  describe "issue/4" do
    test "produces a Phoenix.Token-decodable token for the supplied binding" do
      token = issue(:room_a, "page", "test-instance-id", nil)

      assert {:ok, {"test-instance-id", nil, :room_a, "page", _created_at}} =
               "SECRET_KEY_BASE"
               |> System.fetch_env!()
               |> Phoenix.Token.verify("hologram subscription receipt", token)
    end

    test "stamps a fresh created_at on the receipt" do
      time_before = System.system_time(:millisecond)
      token = issue(:room_a, "page", "test-instance-id", nil)
      time_after = System.system_time(:millisecond)

      assert {:ok, receipt} = verify(token)
      assert receipt.created_at >= time_before
      assert receipt.created_at <= time_after
    end

    test "round-trips the supplied fields" do
      token = issue({:room, 42}, "comp_1", "test-instance-id", 7)

      assert {:ok, receipt} = verify(token)
      assert receipt.channel == {:room, 42}
      assert receipt.cid == "comp_1"
      assert receipt.instance_id == "test-instance-id"
      assert receipt.user_id == 7
    end
  end

  describe "verify/2" do
    test "returns :invalid for a tampered token" do
      token = issue(:room_a, "page", "test-instance-id", nil)
      tampered = token <> "x"

      assert verify(tampered) == {:error, :invalid}
    end

    test "returns :expired when the token is older than max_age" do
      token = issue(:room_a, "page", "test-instance-id", nil)

      assert verify(token, max_age: -1) == {:error, :expired}
    end
  end
end
