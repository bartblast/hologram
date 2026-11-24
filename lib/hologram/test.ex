defmodule Hologram.Test do
  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.DB.SchemaReconciler
  alias Hologram.MisuseError
  alias Hologram.Test.DatabaseBootstrap

  @doc """
  Runs the rest of the calling process as the given user and returns that user unchanged,
  which makes it usable directly in a setup block:

      setup do
        {:ok, user: as_user(create_user())}
      end

  Takes the user entity, a bare user id, or nil to run as a signed-out visitor from this
  point on, whom the rules judge as an anonymous session. A test that sets no actor at all runs as
  trusted server code, past every rule.

  The session lives in the test process, so a controller test of an app's own route runs under it,
  while in production that route has no session and reads and writes past the rules. Don't rely on
  such a test to show that a rule protects the route.

  Raises Hologram.MisuseError when given a user struct whose id is nil - the test would run as a
  signed-out visitor instead of the user it names, and could pass without exercising what it was
  written for.
  """
  @spec as_user(struct | Hologram.Server.identity_id() | nil) ::
          struct | Hologram.Server.identity_id() | nil
  def as_user(user_or_id) do
    user_or_id
    |> actor_user_id()
    |> Auth.Context.put_actor()

    user_or_id
  end

  @doc """
  Runs the given function as the given user and returns its result, restoring the previous
  actor afterwards - the form for scenes with several actors:

      as_user(author, fn -> DB.create(post) end)

  That write is evaluated as the user's :create - every write under an acting user is
  evaluated against the verb's own rules, an update's by the fields it changes. A read inside
  the block is filtered by the user's :read policies the same way.

  Takes the user entity, a bare user id, or nil to run the function as a signed-out visitor,
  whom the rules judge as an anonymous session.

  Raises Hologram.MisuseError when given a user struct whose id is nil, as its single-argument
  counterpart does.
  """
  @spec as_user(struct | Hologram.Server.identity_id() | nil, (-> any)) :: any
  def as_user(user_or_id, fun) do
    user_id = actor_user_id(user_or_id)

    Auth.Context.with_actor(user_id, fun)
  end

  @doc """
  Starts Hologram for feature/browser tests.

  Runs the Hologram compiler, restarts the application with the full supervisor
  tree, and converges the database schema to the app's model. Call this in your
  `test_helper.exs`, after `ExUnit.start()`, before running tests that need Hologram
  pages served in the browser.

      # test_helper.exs
      ExUnit.start()
      Hologram.Test.setup()

  When the app declares entities, every test run gets a fresh database of its own, named after
  the configured test database with a suffix of the run's own, so two runs against one server
  never touch each other's tables, and the configured database itself is never created or
  written to. The configured role must be allowed to create databases. Each run drops the
  databases earlier runs left behind that nothing is connected to anymore.
  """
  @spec setup() :: :ok
  def setup do
    System.put_env("HOLOGRAM_START", "1")

    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    Mix.Tasks.Compile.Hologram.run(force?: true)

    Application.stop(:hologram)

    # While the app is stopped, so no pool is connected when the config is pointed at the run's
    # database, and the start connects there.
    DatabaseBootstrap.run_once!()

    {:ok, _started} = Application.ensure_all_started(:hologram)

    converge_schema()
  end

  # A bare nil asks for a signed-out visitor deliberately, but a user struct carrying a nil id asks
  # for one by accident, and the outcome is silent: the test would exercise neither the policy nor
  # the gate it was written for.
  defp actor_user_id(%{__struct__: module, id: nil}) do
    raise MisuseError,
      message:
        "cannot act as #{inspect(module)} with a nil id - it would run as a signed-out visitor instead of that user, so an authorization test would pass for the wrong reason"
  end

  defp actor_user_id(%{id: id}), do: id

  defp actor_user_id(id), do: id

  # The test env starts the pool and nothing else - dev converges at boot and every other env
  # applies the migration history, while a test app's schema is its helper's to manage. The run's
  # database is fresh, so a run converges from scratch, and this is the only thing that builds the
  # layout. A no-op when the app declares no entities, which leaves the database unstarted.
  defp converge_schema do
    if Process.whereis(DB) do
      SchemaReconciler.reconcile(DB.reconciliation_context())
    end

    :ok
  end
end
