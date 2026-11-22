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

  @compile {:no_warn_undefined, [Ecto.Adapter, Ecto.Repo]}

  @registry Ecto.Repo.Registry

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

  defp ecto_adapter, do: Ecto.Adapter

  defp ecto_repo, do: Ecto.Repo

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
