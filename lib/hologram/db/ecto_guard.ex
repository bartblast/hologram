defmodule Hologram.DB.EctoGuard do
  @moduledoc false

  # What the database gateway knows about Ecto. An app can run an Ecto repo beside the data layer
  # in one database, each on a connection pool of its own, so a transaction on one side doesn't
  # hold the other side's statements: nested in each other they commit separately.
  #
  # Ecto is not a dependency of Hologram. Every repo that is running counts, rather than the ones
  # an app lists under :ecto_repos, because in an umbrella the repo usually belongs to a sibling
  # of the app that depends on Hologram, and a dynamic repo isn't listed anywhere. Ecto's modules
  # are reached through ecto_adapter/0 and ecto_repo/0, since neither the compiler nor Dialyzer
  # can see them in a build without Ecto.

  alias Hologram.DB.Connection

  @compile {:no_warn_undefined, [Ecto.Adapter, Ecto.Repo]}

  @init_event [:ecto, :repo, :init]

  @registry Ecto.Repo.Registry

  @doc """
  Starts watching the queries of every Ecto repo, so that one run inside a data layer transaction
  fails that transaction (see Hologram.DB.Connection.record_ecto_call/2). Safe to call again.

  Ecto can't be stopped at the call: telemetry catches what a handler raises and detaches it, so
  the handlers only record. A repo that starts later is picked up through Ecto's init event, which
  is attached even when Ecto isn't running yet, since Hologram may start first. One already running,
  like a repo in an umbrella sibling or under Hologram.Test.setup/0, is picked up here. The given
  registry is the name Ecto's repo registry runs under.
  """
  @spec attach(atom) :: :ok
  def attach(registry \\ @registry) do
    attach_handler(@init_event, &__MODULE__.handle_repo_init/4)

    if Process.whereis(registry) do
      Enum.each(running_repos(), &attach_running_repo/1)
    end

    :ok
  end

  @doc """
  Telemetry handler of a repo's query event: records the query when the calling process is inside
  a data layer transaction.
  """
  @spec handle_query(list(atom), map, map, any) :: :ok
  def handle_query(_event, _measurements, metadata, _config) do
    repo = Map.get(metadata, :repo)
    query = Map.get(metadata, :query)
    statement = if is_binary(query), do: query

    Connection.record_ecto_call(repo, statement)
  end

  @doc """
  Telemetry handler of Ecto's repo init event: starts watching the queries of the repo starting.
  """
  @spec handle_repo_init(list(atom), map, map, any) :: :ok
  def handle_repo_init(_event, _measurements, metadata, _config) do
    with %{opts: opts} when is_list(opts) <- metadata,
         prefix when is_list(prefix) <- Keyword.get(opts, :telemetry_prefix) do
      prefix
      |> query_event_name()
      |> attach_handler(&__MODULE__.handle_query/4)
    end

    :ok
  catch
    # Telemetry detaches a handler that fails, and no repo started later would be watched. A
    # prefix telemetry can't attach to, like one holding strings, fails here.
    _kind, _reason -> :ok
  end

  @doc """
  Returns the first running Ecto repo with a transaction open in the calling process, or nil.

  A transaction Ecto's SQL sandbox holds for a test doesn't count, only one the code opened. In an
  app without Ecto this is one process lookup. The given registry is the name Ecto's repo registry
  runs under.
  """
  @spec open_transaction_repo(atom) :: module | nil
  def open_transaction_repo(registry \\ @registry) do
    if Process.whereis(registry) do
      Enum.find_value(running_repos(), &repo_in_transaction/1)
    end
  end

  defp attach_handler(event, handler) do
    case :telemetry.attach({__MODULE__, event}, event, handler, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  # Skips a repo it can't read rather than failing: this runs while Hologram boots, and
  # query_event/1 may rerun the app's own init/2 callback.
  defp attach_running_repo(repo) do
    repo
    |> ecto_adapter().lookup_meta()
    |> query_event()
    |> attach_handler(&__MODULE__.handle_query/4)
  catch
    _kind, _reason -> :ok
  end

  defp ecto_adapter, do: Ecto.Adapter

  defp ecto_repo, do: Ecto.Repo

  # ecto_sql's meta holds the event the repo was started with, a prefix from its start options
  # included, which the repo's config doesn't know about.
  defp query_event(%{telemetry: {_repo, _log, event}}), do: event

  defp query_event(%{repo: repo_module}) do
    query_event_name(repo_module.config()[:telemetry_prefix])
  end

  # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
  defp query_event_name(prefix), do: prefix ++ [:query]

  # The repo module names the adapter on every Ecto version, while the meta holds it only on newer
  # ones, and on older ones an :adapter key there is the adapter's own. The meta is the fallback
  # for a repo whose module a code reload removed while it runs, which must not take every data
  # layer statement down with it.
  defp repo_adapter(repo_module, meta) do
    if Code.ensure_loaded?(repo_module) and function_exported?(repo_module, :__adapter__, 0) do
      repo_module.__adapter__()
    else
      Map.get(meta, :adapter)
    end
  end

  # A repo stopping while it's checked counts as having no transaction, so a statement run in the
  # moment a repo goes down inside its own transaction isn't refused. A named repo raises
  # RuntimeError here, its registry row outliving the process for a moment, and a pid ArgumentError.
  defp repo_in_transaction(repo) do
    %{repo: repo_module} = meta = ecto_adapter().lookup_meta(repo)
    adapter = repo_adapter(repo_module, meta)

    if function_exported?(adapter, :in_transaction?, 1) and adapter.in_transaction?(meta) do
      repo_module
    end
  rescue
    _error in [ArgumentError, RuntimeError] -> nil
  end

  # Ecto.Repo.all_running/0 came in Ecto 3.6.2. The module is loaded first, because
  # function_exported?/3 answers false for one that isn't loaded yet.
  defp running_repos do
    repo_module = ecto_repo()

    if Code.ensure_loaded?(repo_module) and function_exported?(repo_module, :all_running, 0) do
      repo_module.all_running()
    else
      []
    end
  rescue
    # The registry's table went away with the Ecto application.
    ArgumentError -> []
  end
end
