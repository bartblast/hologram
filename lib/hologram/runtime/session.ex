defmodule Hologram.Runtime.Session do
  @moduledoc false

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
end
