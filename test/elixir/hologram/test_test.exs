defmodule Hologram.TestTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Test, only: [as_user: 1, as_user: 2]

  alias Hologram.AuthContext
  alias Hologram.Entity
  alias Hologram.Test.Fixtures.Entity.Module14

  describe "as_user/1" do
    test "sets the actor for the rest of the process" do
      as_user("user_id_1")

      assert AuthContext.actor_user_id() == "user_id_1"
    end

    test "takes the user entity" do
      user = Entity.new(Module14, email: "user_1@example.com")

      as_user(user)

      assert AuthContext.actor_user_id() == user.id
    end

    test "returns the given user" do
      user = Entity.new(Module14, email: "user_2@example.com")

      assert as_user(user) == user
      assert as_user("user_id_2") == "user_id_2"
    end
  end

  describe "as_user/2" do
    test "sets the actor for the duration of the function" do
      assert as_user("user_id_3", fn -> AuthContext.actor_user_id() end) == "user_id_3"
      assert AuthContext.actor_user_id() == nil
    end

    test "takes the user entity" do
      user = Entity.new(Module14, email: "user_3@example.com")

      assert as_user(user, fn -> AuthContext.actor_user_id() end) == user.id
    end

    test "restores the enclosing actor afterwards" do
      as_user("user_id_4")
      as_user("user_id_5", fn -> :ok end)

      assert AuthContext.actor_user_id() == "user_id_4"
    end
  end
end
