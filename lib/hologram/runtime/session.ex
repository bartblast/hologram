defmodule Hologram.Runtime.Session do
  @moduledoc false

  # TODO: consider moving to Hologram.Server (Server-struct concept) when splitting up Hologram.Runtime

  # TODO: When standalone Hologram mode is wired, refactor this module into a
  # mode-aware delegator over Hologram.Runtime.Session.Embedded (extracted from
  # the current body) and Hologram.Runtime.Session.Standalone (already preserved).
  # Today this module only exposes the Phoenix-backed (embedded-mode) path.

  @session_id_key :hologram_session_id
  @user_id_key :hologram_user_id

  @type op :: :delete | {:put, any}

  @doc """
  Returns the application-level entries from the Phoenix session, with
  Hologram-managed keys (session_id, user_id) excluded.
  """
  @spec get_session(Plug.Conn.t()) :: map
  def get_session(conn) do
    conn
    |> Plug.Conn.get_session()
    |> Map.drop([Atom.to_string(@session_id_key), Atom.to_string(@user_id_key)])
  end

  @doc """
  Returns the Hologram session ID from the Phoenix session, or `nil` if absent.
  """
  @spec get_session_id(Plug.Conn.t()) :: String.t() | nil
  def get_session_id(conn) do
    Plug.Conn.get_session(conn, @session_id_key)
  end

  @doc """
  Returns the authenticated Hologram user ID from the Phoenix session, or
  `nil` if absent.
  """
  @spec get_user_id(Plug.Conn.t()) :: any
  def get_user_id(conn) do
    Plug.Conn.get_session(conn, @user_id_key)
  end

  @doc """
  Returns the tag of the identity the conn's session holds: who is logged in, in which session.

  The client stamps the pages it saves for Back and Forward with the tag they were rendered
  under, and restores one only while the tag is the same, so that a page never comes back for
  another user than the one it was rendered for. The tag changes with the Hologram session ID
  (a new session) and with the user ID (a login or a logout), and with nothing else the session
  holds.

  The tag is a digest only for its form, a fixed 43 characters that fit in a response header
  whatever the user ID is. It hides nothing, and the server never trusts it.
  """
  @spec identity_tag(Plug.Conn.t()) :: String.t()
  def identity_tag(conn) do
    data = :erlang.term_to_binary({get_session_id(conn), get_user_id(conn)}, [:deterministic])

    :sha256
    |> :crypto.hash(data)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Ensures a Hologram session ID is present in the Phoenix session.

  Mints a UUIDv4 under the `#{inspect(@session_id_key)}` key if absent.
  Idempotent: subsequent calls return the conn unchanged.
  """
  @spec init(Plug.Conn.t()) :: Plug.Conn.t()
  def init(conn) do
    case Plug.Conn.get_session(conn, @session_id_key) do
      nil -> Plug.Conn.put_session(conn, @session_id_key, UUID.uuid4())
      _session_id -> conn
    end
  end

  @doc """
  Persists the authenticated Hologram user ID in the Phoenix session under the
  `#{inspect(@user_id_key)}` key, or removes the key when `user_id` is `nil`.
  """
  @spec put_user_id(Plug.Conn.t(), any) :: Plug.Conn.t()
  def put_user_id(conn, nil) do
    Plug.Conn.delete_session(conn, @user_id_key)
  end

  def put_user_id(conn, user_id) do
    Plug.Conn.put_session(conn, @user_id_key, user_id)
  end
end
