defmodule Hologram.Runtime.ReplicaIdentityTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Runtime.ReplicaIdentity

  @replica_id "test-replica-id"
  @session_id "test-session-id"
  @user_id "test-user-id"

  describe "issue/3" do
    test "binds the id to the user when somebody is signed in" do
      token = issue(@replica_id, @session_id, @user_id)

      assert {:ok, {@replica_id, {:user, @user_id}}} =
               "SECRET_KEY_BASE"
               |> System.fetch_env!()
               |> Phoenix.Token.verify("hologram replica identity", token)
    end

    test "binds the id to the session when nobody is" do
      token = issue(@replica_id, @session_id, nil)

      assert {:ok, {@replica_id, {:session, @session_id}}} =
               "SECRET_KEY_BASE"
               |> System.fetch_env!()
               |> Phoenix.Token.verify("hologram replica identity", token)
    end
  end

  describe "issue_for/2" do
    test "binds the id to the given user" do
      token = issue_for(@replica_id, {:user, @user_id})

      assert verify(token, @replica_id, "another-session", @user_id) == :ok
    end

    test "binds the id to the given session" do
      token = issue_for(@replica_id, {:session, @session_id})

      assert verify(token, @replica_id, @session_id, nil) == :ok
    end
  end

  describe "verified_subject/4" do
    test "answers the user a user-bound identity names" do
      token = issue(@replica_id, @session_id, @user_id)

      assert verified_subject(token, @replica_id, @session_id, @user_id) ==
               {:ok, {:user, @user_id}}
    end

    test "answers the session a session-bound identity names" do
      token = issue(@replica_id, @session_id, nil)

      assert verified_subject(token, @replica_id, @session_id, nil) ==
               {:ok, {:session, @session_id}}
    end

    test "answers the session after somebody signed in on it" do
      token = issue(@replica_id, @session_id, nil)

      assert verified_subject(token, @replica_id, @session_id, @user_id) ==
               {:ok, {:session, @session_id}}
    end

    test "refuses an identity of another user" do
      token = issue(@replica_id, @session_id, "another-user")

      assert verified_subject(token, @replica_id, @session_id, @user_id) ==
               {:error, :mismatch}
    end

    test "refuses a statement that isn't genuine" do
      assert verified_subject("not-a-statement", @replica_id, @session_id, nil) ==
               {:error, :invalid}
    end
  end

  describe "verify/4" do
    test "accepts a user-bound identity from any of that user's sessions" do
      token = issue(@replica_id, @session_id, @user_id)

      assert verify(token, @replica_id, "another-session", @user_id) == :ok
    end

    test "accepts a session-bound identity from its own session" do
      token = issue(@replica_id, @session_id, nil)

      assert verify(token, @replica_id, @session_id, nil) == :ok
    end

    test "accepts a session-bound identity after somebody signed in on that session" do
      token = issue(@replica_id, @session_id, nil)

      assert verify(token, @replica_id, @session_id, @user_id) == :ok
    end

    test "refuses an identity bound to another user" do
      token = issue(@replica_id, @session_id, "another-user")

      assert verify(token, @replica_id, @session_id, @user_id) == {:error, :mismatch}
    end

    test "refuses a user-bound identity presented by an anonymous session" do
      token = issue(@replica_id, @session_id, @user_id)

      assert verify(token, @replica_id, @session_id, nil) == {:error, :mismatch}
    end

    test "refuses a session-bound identity from another session" do
      token = issue(@replica_id, @session_id, nil)

      assert verify(token, @replica_id, "another-session", nil) == {:error, :mismatch}
    end

    test "refuses a statement about another replica" do
      token = issue(@replica_id, @session_id, nil)

      assert verify(token, "another-replica", @session_id, nil) == {:error, :mismatch}
    end

    test "refuses a statement that is not genuine" do
      token = issue(@replica_id, @session_id, nil)

      assert verify(token <> "x", @replica_id, @session_id, nil) == {:error, :invalid}
    end
  end
end
