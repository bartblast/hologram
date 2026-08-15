defmodule HologramClusterTests.MigrationHelpers do
  @moduledoc """
  The vocabulary the migration scenarios are written in.

  Every scenario works on one database - the migrations database, which no other
  cluster test touches - and drives it from two sides: this node plants and inspects
  state directly, while peers reach it by booting the app as a production instance.
  """

  alias Hologram.DB.Config
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity.Model
  alias Hologram.Migration.Loader
  alias Hologram.Migrator
  alias Hologram.Reflection
  alias HologramClusterTests.Cluster
  alias HologramClusterTests.HTTPClient

  @drop_statements [
    ~s(DROP SCHEMA IF EXISTS "hologram_system" CASCADE),
    ~s(DROP SCHEMA IF EXISTS "hologram_data" CASCADE)
  ]

  @doc """
  Returns the applied migration versions with their timestamps, oldest first.

  The timestamp is what distinguishes a version that was applied once from one that
  was applied again: re-application would move it.
  """
  @spec applied_version_rows() :: [{String.t(), DateTime.t()}]
  def applied_version_rows do
    statement = ~s(SELECT "version", "applied_at" FROM "hologram_system"."migration")

    with_migrations_db(fn ->
      {:ok, %{rows: rows}} = Connection.query(statement)

      rows
      |> Enum.map(fn [version, applied_at] -> {version, applied_at} end)
      |> Enum.sort()
    end)
  end

  @doc """
  Boots the app on the given peer, expecting it to refuse, and returns the message of
  the exception that stopped it.

  A refused boot arrives as a supervision failure wrapped in several layers of
  start-child tuples - the message is what the scenario is about, so it is dug out
  rather than asserted through the wrapping.
  """
  @spec boot_error_message(map) :: String.t()
  def boot_error_message(peer) do
    {:error, reason} = Cluster.boot_app(peer)

    find_message(reason)
  end

  @doc """
  Returns the project's migration chain, in order.
  """
  @spec migrations() :: [%{atom => any}]
  def migrations do
    Loader.load_dir!(Loader.migrations_dir())
  end

  @doc """
  Returns the name of the database the migration scenarios apply their chain to.
  """
  @spec migrations_database() :: String.t()
  def migrations_database do
    "hologram_cluster_tests_migrations"
  end

  @doc """
  Returns the model the project's entity declarations produce.
  """
  @spec model() :: %{atom => any}
  def model do
    Model.from_modules(Reflection.list_entities(), Reflection.list_roles())
  end

  @doc """
  Applies the first `count` migrations of the chain to the migrations database, as a
  production instance would, and returns the model they leave behind.

  A partially applied chain is what a node killed mid-deploy leaves behind: per-file
  transactions make "the applier stopped after file N" and "only N files were applied"
  the same database state, so planting it needs no timing.
  """
  @spec plant_applied_prefix!(non_neg_integer) :: %{atom => any}
  def plant_applied_prefix!(count) do
    context = prod_context()
    prefix = Enum.take(migrations(), count)

    with_migrations_db(fn ->
      {:ok, _status} = Connection.transaction(fn -> Migrator.ensure_managed!(context) end)

      Migrator.apply_pending(prefix, Model.empty(), context)
    end)
  end

  @doc """
  Returns the guard facts and marker diagnostics of a production instance of this app.

  The otp_app and env must be what a peer running as `:prod` derives for itself, or
  the marker this writes would refuse the peer that finds it.
  """
  @spec prod_context() :: %{atom => any}
  def prod_context do
    %{
      otp_app: "hologram_cluster_tests",
      env: "prod",
      hologram_version: to_string(Application.spec(:hologram, :vsn)),
      timestamp: DateTime.utc_now(:microsecond)
    }
  end

  @doc """
  Returns the context of a schema reconciliation run against the migrations database.

  Mirrors the shape `Hologram.DB.reconciliation_context/0` builds: the derived mapping
  plus the guard facts and marker diagnostics. Used to claim the database for the OTHER
  mechanism, which is a state production must refuse rather than adopt.

  The app and env are the booting node's own, so what refuses is the marker's MECHANISM
  rather than its identity - a mismatched app or env is refused a step earlier, by a
  different guard with its own message.
  """
  @spec reconciliation_context() :: %{atom => any}
  def reconciliation_context do
    %{
      mapping: Mapper.derive!(Reflection.list_entities()),
      otp_app: "hologram_cluster_tests",
      env: "prod",
      hologram_version: to_string(Application.spec(:hologram, :vsn)),
      timestamp: DateTime.utc_now(:microsecond)
    }
  end

  @doc """
  Drops the Hologram schemas of the migrations database, leaving it virgin.
  """
  @spec reset_migrations_database!() :: :ok
  def reset_migrations_database! do
    connection_pid = start_migrations_db_connection()

    try do
      Enum.each(@drop_statements, &Postgrex.query!(connection_pid, &1, []))
    after
      GenServer.stop(connection_pid)
    end
  end

  @doc """
  Returns whether the given peer serves pages.

  A peer that applied its chain and came up answers this. One that refused its boot
  never binds its port, so the connection is refused rather than answered - a state
  this reports as false, since "did the node come up" is the question being asked, and
  the HTTP client treats an unreachable target as a broken premise.
  """
  @spec serving?(map) :: boolean
  def serving?(peer) do
    HTTPClient.get("http://localhost:#{peer.port}/plain").status == 200
  rescue
    MatchError -> false
  end

  @doc """
  Starts a peer running as a production instance against the migrations database.

  The connection settings are read from this node's resolved configuration, so the
  peer reaches the same server this node plants state on.
  """
  @spec start_migration_peer(pos_integer, keyword) :: map
  def start_migration_peer(index, opts \\ []) do
    Cluster.start_peer(
      index,
      Keyword.merge(
        [hologram_env: "prod", app_env: [{:hologram, :database, migrations_db_opts()}]],
        opts
      )
    )
  end

  @doc """
  Runs the given function with this node's queries routed to the migrations database.
  """
  @spec with_migrations_db((-> any)) :: any
  def with_migrations_db(fun) do
    connection_pid = start_migrations_db_connection()

    try do
      Connection.with_connection(connection_pid, fun)
    after
      GenServer.stop(connection_pid)
    end
  end

  defp find_message(%{__exception__: true} = error), do: Exception.message(error)

  defp find_message([]), do: nil

  defp find_message([head | tail]), do: find_message(head) || find_message(tail)

  defp find_message(term) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> find_message()
  end

  defp find_message(_other), do: nil

  defp migrations_db_opts do
    :hologram
    |> Application.get_env(:database, [])
    |> Config.resolve!(:test)
    |> Keyword.put(:database, migrations_database())
  end

  defp start_migrations_db_connection do
    database_opts = migrations_db_opts()

    {:ok, connection_pid} =
      Postgrex.start_link(
        database: database_opts[:database],
        hostname: database_opts[:host],
        password: database_opts[:password],
        port: database_opts[:port],
        username: database_opts[:user]
      )

    connection_pid
  end
end
