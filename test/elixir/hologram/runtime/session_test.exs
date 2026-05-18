defmodule Hologram.Runtime.SessionTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Runtime.Session

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

  describe "get_session/1" do
    test "strips the session_id key while preserving app entries" do
      conn = conn_with_session(%{@session_id_key => "abc", "role" => "admin"})

      assert get_session(conn) == %{"role" => "admin"}
    end

    test "strips the user_id key while preserving app entries" do
      conn = conn_with_session(%{@user_id_key => 42, "role" => "admin"})

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
  end

  describe "init/1" do
    test "mints a UUIDv4 session ID when absent" do
      conn = init(conn_with_empty_session())

      assert {:ok, _info} =
               conn
               |> Plug.Conn.get_session(@session_id_key)
               |> UUID.info()
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
end
