defmodule Hologram.Auth.Context do
  @moduledoc false

  # The ambient actor of the current process. Framework wrappers set it around the work they
  # run, and Hologram.Test.as_user/1,2 is the sanctioned test-only door.
  #
  # The guarantee is about where identity comes from, not about what server code is able to
  # call: the actor always traces to an authenticated session, and nothing a client sends -
  # params, mutation args, envelopes - ever becomes it. Server code is trusted by
  # construction and already reads and writes past every policy through the DB verbs, so
  # neither setter is a boundary against it. Shipping no act-as-user API keeps impersonation
  # off the app-facing surface, which is a surface decision, not an enforced one.
  #
  # The actor is process-local and is not inherited. Work moved off the request process - a task,
  # a spawned process, a call into a GenServer - starts with no actor, and no actor IS the trusted
  # tier, so a gate that denies in the request process permits there instead. Framework code
  # continuing a session's work in another process re-establishes identity with with_actor/2.

  alias Hologram.Server

  @actor_key {__MODULE__, :actor_user_id}

  @doc """
  Returns the user id of the actor set for the calling process, or nil when no actor is set (an anonymous session).
  """
  @spec actor_user_id() :: Server.identity_id() | nil
  def actor_user_id do
    Process.get(@actor_key)
  end

  @doc false
  # Refuses a value no user is identified by, as with_actor/2 does.
  @spec put_actor(Server.identity_id() | nil) :: :ok
  def put_actor(user_id) do
    Process.put(@actor_key, Server.validate_user_id!(user_id))

    :ok
  end

  @doc """
  Runs the given function with the given user id set as the calling process' actor and returns its result.
  The actor set before the call is restored afterwards, raised exceptions included, so nested calls compose.
  Raises Hologram.MisuseError for a value no user is identified by, before the function runs and with the
  actor left as it was - so no work runs as a user id like false, which the checks testing for an actor
  would read as none.
  """
  @spec with_actor(Server.identity_id() | nil, (-> any)) :: any
  def with_actor(user_id, fun) do
    Server.validate_user_id!(user_id)

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
