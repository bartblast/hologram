defmodule Hologram.Runtime.SessionTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Runtime.Session

  @identity_stamp_key :hologram_identity_stamp
  @session_id_key :hologram_session_id
  @user_id_key :hologram_user_id

  defp conn_with_empty_session do
    :get
    |> Plug.Test.conn("/")
    |> Plug.Test.init_test_session(%{})
  end

  defp conn_with_session(session) do
    :get
    |> Plug.Test.conn("/")
    |> Plug.Test.init_test_session(session)
  end

  defp identity_tag_of(session) do
    session
    |> conn_with_session()
    |> identity_tag()
  end

  describe "get_session/1" do
    test "strips the identity stamp key while preserving app entries" do
      conn = conn_with_session(%{@identity_stamp_key => 123, "role" => "admin"})

      assert get_session(conn) == %{"role" => "admin"}
    end

    test "strips the session_id key while preserving app entries" do
      conn = conn_with_session(%{@session_id_key => "abc", "role" => "admin"})

      assert get_session(conn) == %{"role" => "admin"}
    end

    test "strips the user_id key while preserving app entries" do
      conn = conn_with_session(%{@user_id_key => 42, "role" => "admin"})

      assert get_session(conn) == %{"role" => "admin"}
    end

    test "strips the CSRF token key while preserving app entries" do
      conn = conn_with_session(%{"hologram_csrf_token" => "token", "role" => "admin"})

      assert get_session(conn) == %{"role" => "admin"}
    end
  end

  describe "get_session_id/1" do
    test "returns the session ID when present" do
      existing_id = "existing-session-id"
      conn = conn_with_session(%{@session_id_key => existing_id})

      assert get_session_id(conn) == existing_id
    end

    test "returns nil when no session ID is present" do
      assert get_session_id(conn_with_empty_session()) == nil
    end
  end

  describe "get_user_id/1" do
    test "returns the user ID when present" do
      existing_id = "existing-user-id"
      conn = conn_with_session(%{@user_id_key => existing_id})

      assert get_user_id(conn) == existing_id
    end

    test "returns nil when no user ID is present" do
      assert get_user_id(conn_with_empty_session()) == nil
    end

    test "returns nil for a value persisted before it was refused" do
      for user_id <- [false, true, :admin, <<255, 254>>] do
        conn = conn_with_session(%{@user_id_key => user_id})

        assert get_user_id(conn) == nil
      end
    end
  end

  describe "identity_tag/1" do
    test "is the same for the same session ID and user ID" do
      session = %{@session_id_key => "session-1", @user_id_key => 42}

      assert identity_tag_of(session) == identity_tag_of(session)
    end

    test "differs when the session ID differs" do
      refute identity_tag_of(%{@session_id_key => "session-1"}) ==
               identity_tag_of(%{@session_id_key => "session-2"})
    end

    test "differs when the user ID differs, given as a string" do
      refute identity_tag_of(%{@session_id_key => "session-1", @user_id_key => "alice"}) ==
               identity_tag_of(%{@session_id_key => "session-1", @user_id_key => "bob"})
    end

    test "differs when the user ID differs, given as an integer" do
      refute identity_tag_of(%{@session_id_key => "session-1", @user_id_key => 1}) ==
               identity_tag_of(%{@session_id_key => "session-1", @user_id_key => 2})
    end

    test "differs between a logged-in user and no user" do
      refute identity_tag_of(%{@session_id_key => "session-1", @user_id_key => 42}) ==
               identity_tag_of(%{@session_id_key => "session-1"})
    end

    test "tells an integer user ID from the same digits as a string" do
      refute identity_tag_of(%{@session_id_key => "session-1", @user_id_key => 42}) ==
               identity_tag_of(%{@session_id_key => "session-1", @user_id_key => "42"})
    end

    test "ignores the session's other entries" do
      identity = %{@session_id_key => "session-1", @user_id_key => 42}

      assert identity_tag_of(identity) ==
               identity_tag_of(Map.merge(identity, %{"cart" => ["book"], "locale" => "en"}))
    end

    test "is 43 URL-safe characters" do
      tag = identity_tag_of(%{@session_id_key => "session-1", @user_id_key => 42})

      assert tag =~ ~r/\A0\.[A-Za-z0-9_-]{43}\z/
    end

    test "starts with the session's identity stamp" do
      session = %{@identity_stamp_key => 123, @session_id_key => "session-1"}

      assert identity_tag_of(session) =~ ~r/\A123\./
    end

    test "starts with 0 for a session holding no stamp" do
      assert identity_tag_of(%{@session_id_key => "session-1"}) =~ ~r/\A0\./
    end

    test "starts with none for a request with no session" do
      assert identity_tag_of(%{}) =~ ~r/\Anone\./
    end
  end

  describe "stamp_identity/1" do
    test "stamps the session with the current time" do
      before_ms = System.system_time(:millisecond)

      stamp =
        %{@session_id_key => "session-1"}
        |> conn_with_session()
        |> stamp_identity()
        |> Plug.Conn.get_session(@identity_stamp_key)

      assert stamp >= before_ms
      assert stamp <= System.system_time(:millisecond)
    end

    # The server making the next change can have a clock behind the one that made this one.
    test "moves past a stamp that is ahead of this server's clock" do
      ahead = System.system_time(:millisecond) + 60_000

      conn =
        %{@identity_stamp_key => ahead, @session_id_key => "session-1"}
        |> conn_with_session()
        |> stamp_identity()

      assert Plug.Conn.get_session(conn, @identity_stamp_key) == ahead + 1
    end
  end

  describe "init/1" do
    test "mints a UUIDv4 session ID when absent" do
      conn = init(conn_with_empty_session())

      assert {:ok, _info} =
               conn
               |> Plug.Conn.get_session(@session_id_key)
               |> UUID.info()
    end

    test "stamps the new session's identity" do
      conn = init(conn_with_empty_session())

      assert is_integer(Plug.Conn.get_session(conn, @identity_stamp_key))
    end

    test "leaves the stamp of a session already present" do
      session = %{@identity_stamp_key => 123, @session_id_key => "session-1"}

      conn =
        session
        |> conn_with_session()
        |> init()

      assert Plug.Conn.get_session(conn, @identity_stamp_key) == 123
    end

    test "is idempotent when a session ID is already present" do
      existing_id = "existing-session-id"

      conn =
        %{@session_id_key => existing_id}
        |> conn_with_session()
        |> init()

      assert Plug.Conn.get_session(conn, @session_id_key) == existing_id
    end

    test "generates unique session IDs on independent calls" do
      conn_1 = init(conn_with_empty_session())
      conn_2 = init(conn_with_empty_session())

      assert Plug.Conn.get_session(conn_1, @session_id_key) !=
               Plug.Conn.get_session(conn_2, @session_id_key)
    end
  end

  describe "put_user_id/2" do
    test "stores the user ID under the user_id key" do
      conn = put_user_id(conn_with_empty_session(), 42)

      assert Plug.Conn.get_session(conn, @user_id_key) == 42
    end

    test "stores a string user ID" do
      conn = put_user_id(conn_with_empty_session(), "user-1")

      assert Plug.Conn.get_session(conn, @user_id_key) == "user-1"
    end

    test "removes the user_id key when given nil" do
      conn =
        %{@user_id_key => 42}
        |> conn_with_session()
        |> put_user_id(nil)

      assert Plug.Conn.get_session(conn, @user_id_key) == nil
    end

    test "raises Hologram.MisuseError when given a boolean" do
      assert_error Hologram.MisuseError,
                   "User ID must be a UTF-8 string or an integer, but received false",
                   fn ->
                     put_user_id(conn_with_empty_session(), false)
                   end
    end
  end
end
