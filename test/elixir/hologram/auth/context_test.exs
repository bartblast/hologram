defmodule Hologram.Auth.ContextTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Auth.Context

  test "actor_user_id/0" do
    assert actor_user_id() == nil
  end

  describe "with_actor/2" do
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
