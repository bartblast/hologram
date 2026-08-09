defmodule Hologram.AuthTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Auth

  alias Hologram.AuthContext

  describe "user_id/0" do
    test "returns the actor of the calling process" do
      assert AuthContext.with_actor("user_id_1", fn -> user_id() end) == "user_id_1"
    end

    test "returns nil for an anonymous session" do
      assert user_id() == nil
    end
  end
end
