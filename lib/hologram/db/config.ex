defmodule Hologram.DB.Config do
  @moduledoc false

  alias Hologram.Reflection

  @default_pool_size 10

  @default_port 5432

  @discrete_keys [:database, :host, :password, :pool_size, :port, :user]

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
  Returns the child spec of a connection that listens for announcements under the given name.

  A connection of its own, outside the pool: LISTEN belongs to one connection for as long as it
  listens, which a pooled one cannot promise.

  It connects AFTER booting rather than while booting, which is the difference between a database
  that is away for a moment and a node that is gone. Connecting while booting means a database that
  cannot be reached fails this child, and a child that fails fast enough often enough takes its
  supervisor with it - then the database unit, then the node. Every other connection waits and
  retries instead, and listening survives the wait: the channel is registered with the process and
  sent to the server once it connects.

  It does not reconnect on its own, which is what a unit holding one relies on: losing the
  connection ends this process, and whatever listens through it is restarted beside it and listens
  again as it starts. Reconnecting in place would leave that untouched, listening through a
  connection it never re-registered on.
  """
  @spec listener_child_spec(atom) :: Supervisor.child_spec()
  def listener_child_spec(name) do
    opts = connection_opts(name: name, auto_reconnect: false, sync_connect: false)

    %{id: name, start: {Postgrex.Notifications, :start_link, [opts]}}
  end

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
