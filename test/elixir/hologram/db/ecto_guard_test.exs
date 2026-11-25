defmodule Hologram.DB.EctoGuardTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.EctoGuard

  alias Ecto.Adapters.SQL.Sandbox
  alias Hologram.DB.Connection
  alias Hologram.DB.EctoGuard
  alias Hologram.MisuseError
  alias Hologram.Test.EctoRepo

  # Created by the test that removes it again.
  @compile {:no_warn_undefined, __MODULE__.RemovedRepo}

  @insert_sql ~s|INSERT INTO "hologram_data"."test_fixtures_entity_module1" ("id", "created_at", "server_created_at", "server_updated_at", "updated_at", "$revisions") VALUES ($1, now(), now(), now(), now(), '{}')|

  @moduletag :database

  # An adapter whose meta carries no telemetry event, unlike ecto_sql's.
  defmodule StubAdapter do
    @behaviour Ecto.Adapter

    @impl Ecto.Adapter
    defmacro __before_compile__(_env), do: :ok

    @impl Ecto.Adapter
    def checked_out?(_meta), do: false

    @impl Ecto.Adapter
    def checkout(_meta, _config, fun), do: fun.()

    @impl Ecto.Adapter
    def dumpers(_primitive, type), do: [type]

    @impl Ecto.Adapter
    def ensure_all_started(_config, _type), do: {:ok, []}

    @impl Ecto.Adapter
    def init(_config), do: {:ok, Supervisor.child_spec({Agent, fn -> :ok end}, []), %{}}

    @impl Ecto.Adapter
    def loaders(_primitive, type), do: [type]
  end

  defmodule ConfigRepo do
    use Ecto.Repo, otp_app: :hologram, adapter: Hologram.DB.EctoGuardTest.StubAdapter
  end

  defmodule RaisingConfigRepo do
    use Ecto.Repo, otp_app: :hologram, adapter: Hologram.DB.EctoGuardTest.StubAdapter

    @impl Ecto.Repo
    def init(:runtime, _config), do: raise("the config can't be read")

    def init(:supervisor, config), do: {:ok, config}
  end

  defmodule ExitingConfigRepo do
    use Ecto.Repo, otp_app: :hologram, adapter: Hologram.DB.EctoGuardTest.StubAdapter

    @impl Ecto.Repo
    def init(:runtime, _config), do: exit(:config_server_down)

    def init(:supervisor, config), do: {:ok, config}
  end

  defp count_by_id(id) do
    statement =
      ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_entity_module1" WHERE "id" = $1|

    {:ok, %Postgrex.Result{rows: [[count]]}} = Connection.query(statement, [id])

    count
  end

  defp watched?(event) do
    event
    |> :telemetry.list_handlers()
    |> Enum.any?(&(&1.id == {EctoGuard, event}))
  end

  describe "attach/1" do
    setup do
      {:ok, _started} = Application.ensure_all_started(:ecto_sql)

      :ok
    end

    test "fails a data layer transaction an Ecto query ran in and rolls its writes back" do
      attach()
      EctoRepo.start_for_test!(telemetry_prefix: [:hologram_test, :ecto_guard, :query_in_block])
      id = :crypto.strong_rand_bytes(16)

      assert_error MisuseError, ~r/^Hologram\.Test\.EctoRepo ran "SELECT 1" inside/, fn ->
        Connection.transaction(fn ->
          {:ok, _result} = Connection.query(@insert_sql, [id])
          EctoRepo.query!("SELECT 1")
        end)
      end

      assert count_by_id(id) == 0
    end

    test "names the statement of an Ecto transaction nested in a data layer one" do
      attach()
      EctoRepo.start_for_test!(telemetry_prefix: [:hologram_test, :ecto_guard, :nested])
      id = :crypto.strong_rand_bytes(16)

      assert_error MisuseError, ~r/^Hologram\.Test\.EctoRepo ran "SELECT 2" inside/, fn ->
        Connection.transaction(fn ->
          {:ok, _result} = Connection.query(@insert_sql, [id])
          EctoRepo.transaction(fn -> EctoRepo.query!("SELECT 2") end)
        end)
      end

      assert count_by_id(id) == 0
    end

    test "leaves an Ecto query outside a data layer transaction alone" do
      attach()
      EctoRepo.start_for_test!(telemetry_prefix: [:hologram_test, :ecto_guard, :outside])

      EctoRepo.query!("SELECT 1")

      assert Connection.transaction(fn -> :ok end) == {:ok, :ok}
    end

    test "leaves an Ecto query under its SQL sandbox alone" do
      attach()
      pid = EctoRepo.start_for_test!(telemetry_prefix: [:hologram_test, :ecto_guard, :sandbox])
      :ok = Sandbox.checkout(pid)

      EctoRepo.query!("SELECT 1")

      assert Connection.transaction(fn -> :ok end) == {:ok, :ok}
    end

    test "watches a repo that starts afterwards" do
      attach()

      EctoRepo.start_for_test!(telemetry_prefix: [:hologram_test, :ecto_guard, :started_after])

      assert watched?([:hologram_test, :ecto_guard, :started_after, :query])
    end

    test "watches a running repo, with a prefix from its start options" do
      event = [:hologram_test, :ecto_guard, :already_running, :query]
      EctoRepo.start_for_test!(telemetry_prefix: [:hologram_test, :ecto_guard, :already_running])
      :telemetry.detach({EctoGuard, event})

      attach()

      assert watched?(event)
    end

    test "watches a running repo whose meta has no telemetry event, through its config" do
      start_supervised!(ConfigRepo)
      event = [:hologram, :db, :ecto_guard_test, :config_repo, :query]
      :telemetry.detach({EctoGuard, event})

      attach()

      assert watched?(event)
    end

    test "skips a running repo whose config can't be read" do
      start_supervised!(RaisingConfigRepo)

      assert attach() == :ok
    end

    test "skips a running repo whose config exits" do
      start_supervised!(ExitingConfigRepo)

      assert attach() == :ok
    end

    test "attaches to Ecto's init event when Ecto's registry isn't running" do
      assert attach(:hologram_test_no_such_registry) == :ok

      assert watched?([:ecto, :repo, :init])
    end

    test "can be called again" do
      assert attach() == :ok
      assert attach() == :ok
    end
  end

  describe "handle_query/4" do
    test "records the repo and the statement inside a data layer transaction" do
      assert_error MisuseError, ~r/^SomeRepo ran "SELECT 1" inside/, fn ->
        Connection.transaction(fn ->
          handle_query([:event], %{}, %{repo: SomeRepo, query: "SELECT 1"}, nil)
        end)
      end
    end

    test "doesn't raise on a query that isn't a string" do
      assert_error MisuseError, ~r/^SomeRepo ran a query inside/, fn ->
        Connection.transaction(fn ->
          handle_query([:event], %{}, %{repo: SomeRepo, query: :not_a_string}, nil)
        end)
      end
    end
  end

  describe "handle_repo_init/4" do
    test "doesn't raise on metadata without options" do
      assert handle_repo_init([:ecto, :repo, :init], %{}, %{}, nil) == :ok
    end

    test "doesn't raise on a prefix telemetry can't attach to" do
      metadata = %{opts: [telemetry_prefix: ["my_app", "repo"]]}

      assert handle_repo_init([:ecto, :repo, :init], %{}, metadata, nil) == :ok
    end

    test "doesn't raise on an improper list as the prefix" do
      metadata = %{opts: [telemetry_prefix: [:my_app | :repo]]}

      assert handle_repo_init([:ecto, :repo, :init], %{}, metadata, nil) == :ok
    end

    test "doesn't raise on options without a prefix" do
      assert handle_repo_init([:ecto, :repo, :init], %{}, %{opts: []}, nil) == :ok
    end
  end

  describe "open_transaction_repo/1" do
    test "is nil when Ecto's registry isn't running" do
      refute open_transaction_repo(:hologram_test_no_such_registry)
    end

    test "is nil with a running repo and no transaction" do
      EctoRepo.start_for_test!()

      refute open_transaction_repo()
    end

    test "returns the repo inside its transaction" do
      EctoRepo.start_for_test!()

      assert EctoRepo.transaction(fn -> open_transaction_repo() end) == {:ok, EctoRepo}
    end

    test "is nil once the transaction has ended" do
      EctoRepo.start_for_test!()

      {:ok, :done} = EctoRepo.transaction(fn -> :done end)

      refute open_transaction_repo()
    end

    test "doesn't count the transaction Ecto's SQL sandbox holds for a test" do
      pid = EctoRepo.start_for_test!()
      :ok = Sandbox.checkout(pid)

      refute open_transaction_repo()
    end

    test "counts a transaction the code opens under Ecto's SQL sandbox" do
      pid = EctoRepo.start_for_test!()
      :ok = Sandbox.checkout(pid)

      assert EctoRepo.transaction(fn -> open_transaction_repo() end) == {:ok, EctoRepo}
    end

    test "keeps working for a repo whose module a code reload removed" do
      module = __MODULE__.RemovedRepo

      Module.create(
        module,
        quote do
          use Ecto.Repo, otp_app: :hologram, adapter: Ecto.Adapters.Postgres
        end,
        Macro.Env.location(__ENV__)
      )

      # Purged only here: a purge inside the transaction would kill the process running it.
      on_exit(fn ->
        :code.purge(module)
        :code.delete(module)
        :code.purge(module)
      end)

      EctoRepo.start_for_test!(repo: module)

      assert module.transaction(fn ->
               :code.delete(module)
               open_transaction_repo()
             end) == {:ok, module}

      refute open_transaction_repo()
    end

    test "sees a dynamic repo's transaction after the process switched to another repo" do
      other = EctoRepo.start_for_test!()
      repo = EctoRepo.start_for_test!()

      assert {:ok, EctoRepo} =
               EctoRepo.transaction(fn ->
                 EctoRepo.put_dynamic_repo(other)
                 result = open_transaction_repo()
                 EctoRepo.put_dynamic_repo(repo)

                 result
               end)
    end
  end
end
