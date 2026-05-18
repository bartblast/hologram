defmodule Hologram.Realtime.ReceiptTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Realtime.Receipt

  alias Hologram.Realtime.Receipt

  @receipt %Receipt{
    channel: :room_a,
    cid: "page",
    created_at: 1_700_000_000,
    instance_id: "test-instance-id",
    user_id: nil
  }

  describe "sign/1" do
    test "produces a token that Phoenix.Token can decode back into the original payload" do
      token = sign(@receipt)

      assert {:ok, {"test-instance-id", nil, :room_a, "page", 1_700_000_000}} =
               Phoenix.Token.verify(
                 System.fetch_env!("SECRET_KEY_BASE"),
                 "hologram subscription receipt",
                 token
               )
    end

    test "produces a different token for a different receipt payload" do
      other_receipt = %{@receipt | cid: "comp_1"}

      assert sign(@receipt) != sign(other_receipt)
    end
  end
end
