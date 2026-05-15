defmodule Hologram.Runtime.Session do
  @moduledoc false

  # TODO: When standalone Hologram mode is wired, refactor this module into a
  # mode-aware delegator over Hologram.Runtime.Session.Embedded (extracted from
  # the current body) and Hologram.Runtime.Session.Standalone (already preserved).
  # Today this module only exposes the Phoenix-backed (embedded-mode) path.

  @session_id_key :hologram_session_id

  @type op :: :delete | {:put, any}

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
  Fetches the Hologram session ID from the Phoenix session.

  Returns `{:ok, session_id}` when present, `:error` otherwise.
  """
  @spec fetch_id(Plug.Conn.t()) :: {:ok, String.t()} | :error
  def fetch_id(conn) do
    case Plug.Conn.get_session(conn, @session_id_key) do
      nil -> :error
      session_id -> {:ok, session_id}
    end
  end
end
