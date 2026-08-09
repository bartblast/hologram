defmodule Hologram.Auth.Context do
  @moduledoc false

  # The ambient actor of the current process. Framework wrappers set it around the work
  # they run, and Hologram.Test.as_user/1,2 is the sanctioned test-only door - app code
  # gets no setter, so it can never present itself as a different user than its session.

  @actor_key {__MODULE__, :actor_user_id}

  @doc """
  Returns the user id of the actor set for the calling process, or nil when no actor is set (an anonymous session).
  """
  @spec actor_user_id() :: String.t() | nil
  def actor_user_id do
    Process.get(@actor_key)
  end

  @doc false
  @spec put_actor(String.t() | nil) :: :ok
  def put_actor(user_id) do
    Process.put(@actor_key, user_id)

    :ok
  end

  @doc """
  Runs the given function with the given user id set as the calling process' actor and returns its result.
  The actor set before the call is restored afterwards, raised exceptions included, so nested calls compose.
  """
  @spec with_actor(String.t() | nil, (-> any)) :: any
  def with_actor(user_id, fun) do
    previous_user_id = Process.get(@actor_key)
    Process.put(@actor_key, user_id)

    try do
      fun.()
    after
      restore_actor(previous_user_id)
    end
  end

  defp restore_actor(nil), do: Process.delete(@actor_key)

  defp restore_actor(user_id), do: Process.put(@actor_key, user_id)
end
