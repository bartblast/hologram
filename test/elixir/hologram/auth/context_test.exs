defmodule Hologram.Auth.ContextTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Auth.Context

  test "actor_user_id/0" do
    assert actor_user_id() == nil
  end

  describe "actor_entity_id/0" do
    test "returns nil when no actor is set" do
      assert actor_entity_id() == nil
    end

    test "returns the actor's id when it is a user entity's id" do
      user_id = "0190c4e2-7c1f-7b3a-9d4e-1a2b3c4d5e6f"

      assert with_actor(user_id, fn -> actor_entity_id() end) == user_id
    end

    test "returns nil for an id in any other spelling" do
      for user_id <- ["0190C4E2-7C1F-7B3A-9D4E-1A2B3C4D5E6F", 7, "abc"] do
        assert with_actor(user_id, fn -> actor_entity_id() end) == nil
      end
    end
  end

  describe "put_actor/1" do
    test "sets the actor" do
      put_actor("user_id_9")

      assert actor_user_id() == "user_id_9"
    end

    test "raises Hologram.MisuseError for a boolean, leaving the actor as it was" do
      put_actor("user_id_10")

      assert_error Hologram.MisuseError,
                   "User ID must be a UTF-8 string or an integer, but received false",
                   fn ->
                     put_actor(false)
                   end

      assert actor_user_id() == "user_id_10"
    end
  end

  describe "with_actor/2" do
    test "raises Hologram.MisuseError for a boolean before the function runs, leaving the actor as it was" do
      with_actor("user_id_11", fn ->
        assert_error Hologram.MisuseError,
                     "User ID must be a UTF-8 string or an integer, but received true",
                     fn ->
                       with_actor(true, fn -> send(self(), :ran) end)
                     end

        refute_received :ran

        assert actor_user_id() == "user_id_11"
      end)
    end

    test "sets the actor for the duration of the function" do
      assert with_actor("user_id_1", fn -> actor_user_id() end) == "user_id_1"
    end

    test "returns the function result" do
      assert with_actor("user_id_2", fn -> :result_1 end) == :result_1
    end

    test "clears the actor afterwards" do
      with_actor("user_id_3", fn -> :ok end)

      assert actor_user_id() == nil
    end

    test "restores the enclosing actor afterwards" do
      result =
        with_actor("user_id_4", fn ->
          with_actor("user_id_5", fn -> :ok end)

          actor_user_id()
        end)

      assert result == "user_id_4"
    end

    # The actor lives in the process dictionary, so work moved off the request process starts
    # with none - which is the trusted tier, not an anonymous session. Pinned here because the
    # boundary decides which tier spawned work runs in.
    test "leaves a spawned process without an actor" do
      spawned_actor_user_id =
        with_actor("user_id_8", fn ->
          fn -> actor_user_id() end
          |> Task.async()
          |> Task.await()
        end)

      assert spawned_actor_user_id == nil
    end

    test "restores the enclosing actor when the function raises" do
      with_actor("user_id_6", fn ->
        assert_raise RuntimeError, fn ->
          with_actor("user_id_7", fn -> raise "error_1" end)
        end

        assert actor_user_id() == "user_id_6"
      end)

      assert actor_user_id() == nil
    end
  end
end
