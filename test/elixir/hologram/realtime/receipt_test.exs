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
               "SECRET_KEY_BASE"
               |> System.fetch_env!()
               |> Phoenix.Token.verify("hologram subscription receipt", token)
    end

    test "produces a different token for a different receipt payload" do
      other_receipt = %{@receipt | cid: "comp_1"}

      assert sign(@receipt) != sign(other_receipt)
    end
  end

  describe "verify/2" do
    test "decodes a freshly-signed token back into the original receipt" do
      token = sign(@receipt)

      assert verify(token) == {:ok, @receipt}
    end

    test "returns :invalid for a tampered token" do
      token = sign(@receipt)
      tampered = token <> "x"

      assert verify(tampered) == {:error, :invalid}
    end

    test "returns :expired when the token is older than max_age" do
      token = sign(@receipt)

      assert verify(token, max_age: -1) == {:error, :expired}
    end
  end
end
