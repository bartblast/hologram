defmodule Hologram.TestTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Test, only: [as_user: 1, as_user: 2]

  alias Hologram.Auth.Context
  alias Hologram.Test.Fixtures.Entity.Module14

  describe "as_user/1" do
    test "sets the actor for the rest of the process" do
      as_user("user_id_1")

      assert Context.actor_user_id() == "user_id_1"
    end

    test "takes the user entity" do
      user = Module14.new(email: "user_1@example.com")

      as_user(user)

      assert Context.actor_user_id() == user.id
    end

    test "returns the given user" do
      user = Module14.new(email: "user_2@example.com")

      assert as_user(user) == user
      assert as_user("user_id_2") == "user_id_2"
    end

    test "runs anonymously from this point on for a nil id" do
      as_user("user_id_7")

      assert as_user(nil) == nil
      assert Context.actor_user_id() == nil
    end

    test "raises for a user struct with a nil id" do
      expected_msg =
        "cannot act as Hologram.Test.Fixtures.Entity.Module14 with a nil id - an unset actor reads as an anonymous session and writes as trusted code, so an authorization test would pass for the wrong reason"

      assert_error ArgumentError, expected_msg, fn -> as_user(%Module14{}) end
    end
  end

  describe "as_user/2" do
    test "sets the actor for the duration of the function" do
      assert as_user("user_id_3", fn -> Context.actor_user_id() end) == "user_id_3"
      assert Context.actor_user_id() == nil
    end

    test "takes the user entity" do
      user = Module14.new(email: "user_3@example.com")

      assert as_user(user, fn -> Context.actor_user_id() end) == user.id
    end

    test "restores the enclosing actor afterwards" do
      as_user("user_id_4")
      as_user("user_id_5", fn -> :ok end)

      assert Context.actor_user_id() == "user_id_4"
    end

    test "runs the function with no actor for a nil id" do
      as_user("user_id_6")

      assert as_user(nil, fn -> Context.actor_user_id() end) == nil
      assert Context.actor_user_id() == "user_id_6"
    end

    test "raises for a user struct with a nil id" do
      expected_msg =
        "cannot act as Hologram.Test.Fixtures.Entity.Module14 with a nil id - an unset actor reads as an anonymous session and writes as trusted code, so an authorization test would pass for the wrong reason"

      assert_error ArgumentError, expected_msg, fn -> as_user(%Module14{}, fn -> :ok end) end
    end
  end
end
