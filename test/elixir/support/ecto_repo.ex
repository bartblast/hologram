defmodule Hologram.Test.EctoRepo do
  @moduledoc false

  # A real Ecto repo beside the data layer, for the tests of how the two treat each other's
  # transactions. Each test starts its own instance as a dynamic repo, so tests stay async.

  use Ecto.Repo, otp_app: :hologram, adapter: Ecto.Adapters.Postgres

  alias Ecto.Adapters.SQL.Sandbox
  alias Hologram.DB.Config

  @doc """
  Starts an instance of the repo on the test database under the test supervisor, makes it the
  calling process's dynamic repo and returns its pid. The given options override the defaults,
  and `:repo` names another repo module to start instead of this one.
  """
  @spec start_for_test!(keyword) :: pid
  def start_for_test!(opts \\ []) do
    {:ok, _started} = Application.ensure_all_started(:ecto_sql)

    {repo, opts} = Keyword.pop(opts, :repo, __MODULE__)

    config =
      [log: false, name: nil, pool: Sandbox, pool_size: 1]
      |> Keyword.merge(opts)
      |> Config.connection_opts()

    pid =
      ExUnit.Callbacks.start_supervised!(%{
        id: make_ref(),
        start: {repo, :start_link, [config]},
        type: :supervisor
      })

    repo.put_dynamic_repo(pid)

    pid
  end
end
