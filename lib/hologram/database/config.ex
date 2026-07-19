defmodule Hologram.Database.Config do
  @moduledoc false

  alias Hologram.Reflection

  @default_pool_size 10

  @default_port 5432

  @discrete_keys [:database, :host, :password, :pool_size, :port, :user]

  @required_keys [:database, :host, :password, :user]

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

    [
      database: database,
      host: uri.host,
      password: password,
      port: uri.port,
      user: user
    ]
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
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
