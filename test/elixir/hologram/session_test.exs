defmodule Hologram.SessionTest do
  use Hologram.Test.BasicCase, async: true
  alias Hologram.Session

  defp build_conn_with_session_cookie(cookie_value) do
    %Plug.Conn{
      req_cookies: %{"hologram_session" => cookie_value},
      resp_cookies: %{},
      scheme: :https
    }
  end

  defp build_conn_without_session_cookie do
    %Plug.Conn{
      req_cookies: %{},
      resp_cookies: %{},
      scheme: :https
    }
  end

  describe "init/1" do
    test "creates new session when no cookie exists" do
      conn = build_conn_without_session_cookie()

      {updated_conn, session_id} = Session.init(conn)

      assert is_binary(session_id)
      assert String.length(session_id) == 36

      assert session_id =~
               ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

      resp_cookies = updated_conn.resp_cookies
      assert Map.has_key?(resp_cookies, "hologram_session")

      cookie = resp_cookies["hologram_session"]
      assert cookie.http_only == true
      assert cookie.same_site == "Lax"
      assert cookie.secure == true
    end

    test "retrieves existing session when valid cookie exists" do
      # First, create a session to get a valid encrypted cookie
      initial_conn = build_conn_without_session_cookie()
      {conn_after_init, original_session_id} = Session.init(initial_conn)

      # Extract the encrypted cookie value and create a new connection that has it
      encrypted_session = conn_after_init.resp_cookies["hologram_session"].value
      conn_with_session_cookie = build_conn_with_session_cookie(encrypted_session)

      # Now test init with the existing cookie
      {updated_conn, session_id} = Session.init(conn_with_session_cookie)

      assert session_id == original_session_id

      # Should not set a new cookie (resp_cookies should be empty)
      assert updated_conn.resp_cookies == %{}
    end

    test "creates new session when invalid cookie exists" do
      # Create a connection with an invalid/corrupted session cookie
      conn = build_conn_with_session_cookie("invalid_encrypted_data")

      {updated_conn, session_id} = Session.init(conn)

      assert is_binary(session_id)
      assert String.length(session_id) == 36

      assert session_id =~
               ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

      resp_cookies = updated_conn.resp_cookies
      assert Map.has_key?(resp_cookies, "hologram_session")

      cookie = resp_cookies["hologram_session"]
      assert cookie.http_only == true
      assert cookie.same_site == "Lax"
      assert cookie.secure == true
    end

    test "sets secure flag to true for HTTPS connections" do
      conn = Map.put(build_conn_without_session_cookie(), :scheme, :https)

      {updated_conn, _session_id} = Session.init(conn)

      assert updated_conn.resp_cookies["hologram_session"].secure == true
    end

    test "sets secure flag to false for HTTP connections" do
      conn = Map.put(build_conn_without_session_cookie(), :scheme, :http)

      {updated_conn, _session_id} = Session.init(conn)

      assert updated_conn.resp_cookies["hologram_session"].secure == false
    end

    test "generates unique session IDs for different calls" do
      conn_1 = build_conn_without_session_cookie()
      conn_2 = build_conn_without_session_cookie()

      {_updated_conn_1, session_id_1} = Session.init(conn_1)
      {_updated_conn_2, session_id_2} = Session.init(conn_2)

      assert session_id_1 != session_id_2
    end
  end
end
