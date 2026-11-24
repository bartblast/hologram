defmodule Hologram.Runtime.Session do
  @moduledoc false

  # TODO: consider moving to Hologram.Server (Server-struct concept) when splitting up Hologram.Runtime

  # TODO: When standalone Hologram mode is wired, refactor this module into a
  # mode-aware delegator over Hologram.Runtime.Session.Embedded (extracted from
  # the current body) and Hologram.Runtime.Session.Standalone (already preserved).
  # Today this module only exposes the Phoenix-backed (embedded-mode) path.

  alias Hologram.Runtime.CSRFProtection
  alias Hologram.Server

  @identity_stamp_key :hologram_identity_stamp
  @session_id_key :hologram_session_id
  @user_id_key :hologram_user_id

  @type op :: :delete | {:put, any}

  @doc false
  # The keys Hologram keeps its own session state under, which the app doesn't write directly - a
  # value written past Hologram would skip the checks it makes.
  @spec reserved_keys() :: list(String.t())
  def reserved_keys do
    [
      CSRFProtection.session_key(),
      Atom.to_string(@identity_stamp_key),
      Atom.to_string(@session_id_key),
      Atom.to_string(@user_id_key)
    ]
  end

  @doc """
  Returns the application-level entries from the Phoenix session, with
  Hologram-managed keys (CSRF token, identity stamp, session_id, user_id) excluded.
  """
  @spec get_session(Plug.Conn.t()) :: map
  def get_session(conn) do
    conn
    |> Plug.Conn.get_session()
    |> Map.drop(reserved_keys())
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

  A value `put_user_id/2` refuses reads as `nil`: only a session persisted before it was refused
  holds one, and the stale value reads as no user on every request until a sign-in replaces it,
  rather than failing them.
  """
  @spec get_user_id(Plug.Conn.t()) :: Server.identity_id() | nil
  def get_user_id(conn) do
    user_id = Plug.Conn.get_session(conn, @user_id_key)

    if Server.valid_user_id?(user_id), do: user_id
  end

  @doc """
  Returns the tag of the identity the conn's session holds: who is logged in, in which session.

  The client stamps the pages it saves for Back and Forward with the tag they were rendered
  under, and restores one only while the tag is the same, so that a page never comes back for
  another user than the one it was rendered for. The tag changes with the Hologram session ID
  (a new session) and with the user ID (a login or a logout), and with nothing else the session
  holds.

  It starts with the session's identity stamp, then a dot, so that a client hearing about the
  identity from several responses and streams, in any order, can tell which is newer. A request
  with no session has no stamp, and starts with `none`: its cookie was cleared, which no later
  response is going to contradict. The digest is there only for its form, a fixed 43 characters
  that fit in a response header whatever the user ID is. It hides nothing, and the server never
  trusts it.
  """
  @spec identity_tag(Plug.Conn.t()) :: String.t()
  def identity_tag(conn) do
    session_id = get_session_id(conn)
    data = :erlang.term_to_binary({session_id, get_user_id(conn)}, [:deterministic])

    digest =
      :sha256
      |> :crypto.hash(data)
      |> Base.url_encode64(padding: false)

    stamp = if session_id, do: identity_stamp(conn), else: "none"

    "#{stamp}.#{digest}"
  end

  @doc """
  Ensures a Hologram session ID is present in the Phoenix session.

  Mints a UUIDv4 under the `#{inspect(@session_id_key)}` key if absent.
  Idempotent: subsequent calls return the conn unchanged.
  """
  @spec init(Plug.Conn.t()) :: Plug.Conn.t()
  def init(conn) do
    case Plug.Conn.get_session(conn, @session_id_key) do
      nil ->
        conn
        |> Plug.Conn.put_session(@session_id_key, UUID.uuid4())
        |> stamp_identity()

      _session_id ->
        conn
    end
  end

  @doc """
  Persists the authenticated Hologram user ID in the Phoenix session under the
  `#{inspect(@user_id_key)}` key, or removes the key when `user_id` is `nil`.

  Raises `Hologram.MisuseError` for a value no user is identified by (see
  `Hologram.Server.validate_user_id!/1`) - one set on the server struct directly, past
  `Hologram.Server.put_user_id/2`, is caught here before a later request reads it back.
  """
  @spec put_user_id(Plug.Conn.t(), Server.identity_id() | nil) :: Plug.Conn.t()
  def put_user_id(conn, nil) do
    Plug.Conn.delete_session(conn, @user_id_key)
  end

  def put_user_id(conn, user_id) do
    Plug.Conn.put_session(conn, @user_id_key, Server.validate_user_id!(user_id))
  end

  @doc """
  Records that the identity the session holds changed just now.

  The stamp is the current time, moved past the one it replaces, so that it goes up with every
  change made on this session whatever the clocks of the servers making them say. A session with
  no stamp holds the identity it held before stamps existed, which reads as the oldest.
  """
  @spec stamp_identity(Plug.Conn.t()) :: Plug.Conn.t()
  def stamp_identity(conn) do
    stamp = max(System.system_time(:millisecond), identity_stamp(conn) + 1)

    Plug.Conn.put_session(conn, @identity_stamp_key, stamp)
  end

  defp identity_stamp(conn) do
    Plug.Conn.get_session(conn, @identity_stamp_key) || 0
  end
end
