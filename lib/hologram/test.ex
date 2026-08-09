defmodule Hologram.Test do
  alias Hologram.Auth

  @doc """
  Runs the rest of the calling process as the given user and returns that user unchanged,
  which makes it usable directly in a setup block:

      setup do
        {:ok, user: as_user(create_user())}
      end

  Takes the user entity or a bare user id. A test that sets no actor runs as an anonymous
  session.
  """
  @spec as_user(struct | String.t()) :: struct | String.t()
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

  Takes the user entity or a bare user id.
  """
  @spec as_user(struct | String.t(), (-> any)) :: any
  def as_user(user_or_id, fun) do
    user_id = actor_user_id(user_or_id)

    Auth.Context.with_actor(user_id, fun)
  end

  @doc """
  Starts Hologram for feature/browser tests.

  Runs the Hologram compiler and restarts the application with the full
  supervisor tree. Call this in your `test_helper.exs` before running
  tests that need Hologram pages served in the browser.

      # test_helper.exs
      Hologram.Test.setup()
  """
  @spec setup() :: {:ok, [atom()]} | {:error, {atom(), term()}}
  def setup do
    System.put_env("HOLOGRAM_START", "1")

    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    Mix.Tasks.Compile.Hologram.run(force?: true)

    Application.stop(:hologram)
    Application.ensure_all_started(:hologram)
  end

  defp actor_user_id(%{id: id}), do: id

  defp actor_user_id(id), do: id
end
