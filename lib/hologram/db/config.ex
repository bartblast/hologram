defmodule Hologram.DB.Config do
  @moduledoc false

  require Logger

  alias Hologram.Reflection

  @default_pool_size 10

  @default_port 5432

  # How long a held connection may sit idle before it pings the server - Postgrex.SimpleConnection's
  # default, set explicitly so that the check in held_connection_opts/1 reads the value sent.
  @idle_interval_ms :timer.seconds(5)

  # How long a held connection waits between tries while the database refuses it. One log line per
  # connection per try, so not much shorter; below the idle interval, see held_connection_opts/1.
  @reconnect_backoff_ms :timer.seconds(2)

  @discrete_keys [:database, :host, :password, :pool_size, :port, :user]

  @first_statement_timeout_ms :timer.seconds(150)

  @keepalive_statement """
  SELECT
    set_config('tcp_keepalives_idle', '30', false),
    set_config('tcp_keepalives_interval', '10', false),
    set_config('tcp_keepalives_count', '3', false),
    set_config('tcp_user_timeout', '60000', false)
  """

  @required_keys [:database, :host, :password, :user]

  @doc """
  Returns the Postgrex options of the configured database in the current environment,
  with the given overrides applied.

  For a connection opened outside the pool - one that has to stay the same connection
  across several statements, or reach a different database on the same server.
  """
  @spec connection_opts(keyword) :: keyword
  def connection_opts(overrides \\ []) do
    resolved =
      :hologram
      |> Application.get_env(:database, [])
      |> resolve!(Hologram.env())

    Keyword.merge(
      [
        database: resolved[:database],
        hostname: resolved[:host],
        password: resolved[:password],
        port: resolved[:port],
        username: resolved[:user]
      ],
      overrides
    )
  end

  @doc """
  Logs that the calling connection lost its session to the database, then ends it with
  `{:shutdown, :connection_lost}`.

  What a connection started with held_connection_opts/1 does when its session is lost - see there.
  """
  @spec end_lost_session!() :: no_return
  def end_lost_session! do
    name =
      case Process.info(self(), :registered_name) do
        {:registered_name, name} when is_atom(name) -> name
        _no_name -> self()
      end

    Logger.error(
      "#{inspect(name)} lost its connection to the database, ending so that whatever depends on it is restarted with it"
    )

    exit({:shutdown, :connection_lost})
  end

  @doc """
  Returns how long a held connection (see held_connection_opts/1) waits for the answer to its
  session's first statement before it is killed: 150 seconds.

  Postgrex puts no bound on the wait, so a link that went silent as the session opened would hold
  the connection - for good once the server's side acknowledged the statement, about 15 minutes on
  Linux otherwise.

  Long, because a session-mode PgBouncer lets a client log in without a server connection and
  assigns one at the first statement. With its pool full, that statement waits in a queue served
  in order of arrival, and a connection killed while it waits rejoins at the back - a bound shorter
  than the wait would keep it out for as long as others are queued. PgBouncer ends the wait itself
  after its query_wait_timeout, 120 seconds by default, by closing the session, which the
  connection logs as lost and ends on. This bound sits above that default, so the pooler's limit
  comes first. Behind a pooler set to queue for longer, the kill comes first, and logs nothing.
  """
  @spec first_statement_timeout_ms() :: pos_integer
  def first_statement_timeout_ms, do: @first_statement_timeout_ms

  @doc """
  Returns the Postgrex options of a connection held outside the pool for as long as its session
  lasts, with the given overrides applied (see connection_opts/1).

  For a Postgrex.SimpleConnection whose session is the point: a listener's channels are registered
  on it, and the run lock connection's locks are held by it. Such a connection keeps trying its
  FIRST connect, every 2 seconds, and ends once a session it had is lost - its handle_disconnect/1
  calls end_lost_session!/0.

  Trying again rather than failing is the difference between a database that is away for a moment
  and a node that is gone. A connect that fails ends the process otherwise, and while the database
  refuses connections every restart fails within milliseconds - a supervisor gives up on the fourth
  restart within 5 seconds, then the one above it, up to the application. The connection waits
  instead, the way the pool's connections do, and a call made to it meanwhile is answered between
  two tries. A try against a host that drops packets rather than refusing them blocks the process
  until the connect timeout, which can outlast a call's timeout.

  Ending rather than reconnecting, because what was tied to the session is gone with it. A
  listener's announcements sent while it was away are lost without whoever listens through it
  knowing, and a run lock connection's locks are freed by the server. Its supervisor restarts it
  and whatever depends on it, which start over from where they stand.

  `auto_reconnect: true` is what has SimpleConnection try again after a failed connect - it would
  reconnect a lost session too, but the process has ended by then. The backoff has to stay below
  the connection's `:idle_interval`: a call arriving between two tries arms the idle ping, which
  crashes on the missing socket if it fires before the next try. Raises ArgumentError when the
  given overrides break that.
  """
  @spec held_connection_opts(keyword) :: keyword
  def held_connection_opts(overrides \\ []) do
    opts =
      [
        auto_reconnect: true,
        idle_interval: @idle_interval_ms,
        reconnect_backoff: @reconnect_backoff_ms,
        sync_connect: false
      ]
      |> Keyword.merge(overrides)
      |> connection_opts()

    backoff = Keyword.fetch!(opts, :reconnect_backoff)
    idle_interval = Keyword.fetch!(opts, :idle_interval)

    if backoff >= idle_interval do
      raise ArgumentError,
            "the reconnect backoff of a held connection must be below its idle interval, got #{backoff} ms and #{idle_interval} ms"
    end

    opts
  end

  @doc """
  Returns the statement that sets the server keepalives and user timeout of the session it runs
  in - the same figures as the run lock connection's (see Hologram.Job.RunLock).

  A node that vanishes leaves its sessions open on the server until the operating system there
  notices. The keepalives bound that to about a minute when the server has nothing unacknowledged
  on the link, rather than about two hours, and the user timeout when it has, rather than about 15
  minutes. A server whose platform has no user timeout keeps it at 0, and logs that it is not
  supported on each connect.

  Run once the connection is up rather than sent as startup parameters, which PgBouncer refuses
  unless told to ignore them. They bound only a direct connection: behind a pooler or a proxy the
  server's peer is the pooler, and its own keepalives toward the node are what bound how long the
  session lives.
  """
  @spec keepalive_statement() :: String.t()
  def keepalive_statement, do: @keepalive_statement

  @doc """
  Resolves the database connection options for the given environment from the given
  config keyword list (the value of `config :hologram, :database`).

  Discrete keys (:database, :host, :password, :pool_size, :port, :user) are overlaid
  on the environment defaults, and components present in :url win over both. In :dev
  and :test the defaults are localhost with postgres/postgres credentials and the
  "<otp_app>_<env>" database. Other environments have no identity defaults - a missing
  :database, :host, :password or :user raises ArgumentError - while :port and
  :pool_size default to 5432 and 10 everywhere.

  Returns a keyword list with the :database, :host, :password, :pool_size, :port and
  :user options.
  """
  @spec resolve!(keyword, atom) :: keyword
  def resolve!(config, env) do
    url_components =
      config
      |> Keyword.get(:url)
      |> url_components()

    resolved =
      env
      |> defaults()
      |> Keyword.merge(Keyword.take(config, @discrete_keys))
      |> Keyword.merge(url_components)
      |> Keyword.put_new(:pool_size, @default_pool_size)
      |> Keyword.put_new(:port, @default_port)

    validate_required!(resolved, env)

    Enum.sort(resolved)
  end

  @doc """
  Logs that the database refused the keepalive settings (see keepalive_statement/0) with the given
  error, and returns :ok.

  What a connection does whose settings are best effort: they bound only how long the server keeps
  the session of a node that vanished, which nothing needs for being correct.
  """
  @spec warn_keepalives_refused(Exception.t()) :: :ok
  def warn_keepalives_refused(error) do
    Logger.warning(
      "the database refused the session's keepalive settings, a session of a node that vanished may stay open on the server for hours: #{Exception.message(error)}"
    )
  end

  defp defaults(env) when env in [:dev, :test] do
    [
      database: "#{Reflection.otp_app()}_#{env}",
      host: "localhost",
      password: "postgres",
      user: "postgres"
    ]
  end

  defp defaults(_env), do: []

  defp url_components(nil), do: []

  defp url_components(url) do
    uri = URI.parse(url)

    {user, password} =
      case String.split(uri.userinfo || "", ":", parts: 2) do
        [user, password] -> {user, password}
        [user] -> {user, nil}
      end

    database = uri.path && String.trim_leading(uri.path, "/")

    components = [
      database: database,
      host: uri.host,
      password: password,
      port: uri.port,
      user: user
    ]

    Enum.reject(components, fn {_key, value} -> value in [nil, ""] end)
  end

  defp validate_required!(resolved, env) do
    missing = Enum.reject(@required_keys, &Keyword.has_key?(resolved, &1))

    if missing != [] do
      missing_keys = Enum.join(missing, ", ")

      raise ArgumentError,
            "missing database configuration for #{inspect(env)} - set config :hologram, :database with discrete keys or url:, missing: #{missing_keys}"
    end

    :ok
  end
end
