defmodule Hologram.Test do
  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.DB.SchemaReconciler

  @doc """
  Runs the rest of the calling process as the given user and returns that user unchanged,
  which makes it usable directly in a setup block:

      setup do
        {:ok, user: as_user(create_user())}
      end

  Takes the user entity, a bare user id, or nil to run anonymously from this point on. A test
  that sets no actor at all is anonymous too.

  Raises ArgumentError when given a user struct whose id is nil - an unset actor reads as an
  anonymous session and writes as trusted code, so the silent outcome would be a test passing
  without exercising what it was written for.
  """
  @spec as_user(struct | String.t() | nil) :: struct | String.t() | nil
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

  The write is evaluated as the user's :create, the way every write under an acting user is.

  Takes the user entity, a bare user id, or nil to run the function anonymously - the spelling
  for a block that must not carry the enclosing actor.

  Raises ArgumentError when given a user struct whose id is nil, as its single-argument
  counterpart does.
  """
  @spec as_user(struct | String.t() | nil, (-> any)) :: any
  def as_user(user_or_id, fun) do
    user_id = actor_user_id(user_or_id)

    Auth.Context.with_actor(user_id, fun)
  end

  @doc """
  Starts Hologram for feature/browser tests.

  Runs the Hologram compiler, restarts the application with the full supervisor
  tree, and converges the database schema to the app's model. Call this in your
  `test_helper.exs` before running tests that need Hologram pages served in the
  browser.

      # test_helper.exs
      Hologram.Test.setup()
  """
  @spec setup() :: :ok
  def setup do
    System.put_env("HOLOGRAM_START", "1")

    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    Mix.Tasks.Compile.Hologram.run(force?: true)

    Application.stop(:hologram)
    {:ok, _started} = Application.ensure_all_started(:hologram)

    converge_schema()
  end

  # The test env starts the pool and nothing else - dev converges at boot and every other env
  # applies the migration history, while a test app's schema is its helper's to manage. The
  # database bootstrap drops the layout before this runs, so a run converges from scratch, and
  # this is the only thing that puts it back. A no-op when the app declares no entities, which
  # leaves the database unstarted.
  defp converge_schema do
    if Process.whereis(DB) do
      SchemaReconciler.reconcile(DB.reconciliation_context())
    end

    :ok
  end

  # An unset actor is a legal state, and a bare nil asks for it deliberately - but a user struct
  # carrying a nil id asks for it by accident, and the outcome is silent: the test would exercise
  # neither the policy nor the gate it was written for.
  defp actor_user_id(%{__struct__: module, id: nil}) do
    raise ArgumentError,
      message:
        "cannot act as #{inspect(module)} with a nil id - an unset actor reads as an anonymous session and writes as trusted code, so an authorization test would pass for the wrong reason"
  end

  defp actor_user_id(%{id: id}), do: id

  defp actor_user_id(id), do: id
end
