defmodule Hologram.Runtime.SessionTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Runtime.Session

  @session_id_key :hologram_session_id

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

  describe "fetch_session_id/1" do
    test "returns {:ok, session_id} when a session ID is present" do
      existing_id = "existing-session-id"
      conn = conn_with_session(%{@session_id_key => existing_id})

      assert fetch_session_id(conn) == {:ok, existing_id}
    end

    test "returns :error when no session ID is present" do
      assert fetch_session_id(conn_with_empty_session()) == :error
    end
  end
end
