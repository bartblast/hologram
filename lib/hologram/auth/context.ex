defmodule Hologram.Auth.Context do
  @moduledoc false

  # The session the current process is working for. Framework wrappers set it around the work they
  # run, and Hologram.Test.as_user/1,2 is the sanctioned test-only door.
  #
  # A process is in one of two states. With a session, it is doing a request's work, for the
  # session's user or, with a nil user id, for a signed-out visitor, whom the rules judge as an
  # anonymous session. With no session, it is server code no request started, like a seed, a Mix
  # task, a console or a worker, and that is the trusted tier.
  #
  # The guarantee is about where identity comes from, not about what server code is able to
  # call: the actor always traces to an authenticated session, and nothing a client sends -
  # params, mutation args, envelopes - ever becomes it. Server code is trusted by
  # construction and can read and write past every policy by claiming trust, so
  # neither setter is a boundary against it. Shipping no act-as-user API keeps impersonation
  # off the app-facing surface, which is a surface decision, not an enforced one.
  #
  # The session is process-local and is not inherited. Work moved off the request process - a task,
  # a spawned process, a call into a GenServer - starts with no session, which IS the trusted tier,
  # so a gate that denies in the request process permits there instead (#1848). Framework code
  # continuing a session's work in another process re-establishes identity with with_actor/2.

  alias Hologram.Auth
  alias Hologram.Server

  # Holds {:session, user_id}, so a signed-out visitor's nil user id is told from no session.
  @actor_key {__MODULE__, :actor_user_id}

  @doc """
  Returns the user id of the actor set for the calling process, or nil for a signed-out visitor's
  session and when the process has no session. session?/0 tells those two apart.
  """
  @spec actor_user_id() :: Server.identity_id() | nil
  def actor_user_id do
    case Process.get(@actor_key) do
      {:session, user_id} -> user_id
      nil -> nil
    end
  end

  @doc """
  Returns the actor's id as the data layer stores a user - the canonical uuid a user entity's id
  is - or nil when no actor is set and when the actor's id is one no user entity can have, like an
  app's own serial id. Such an actor is still set, so its work is judged rather than trusted, but
  the data layer reads it as a session with no user: nothing records it as anyone.
  """
  @spec actor_entity_id() :: String.t() | nil
  def actor_entity_id do
    Auth.canonical_id(actor_user_id())
  end

  @doc false
  # Refuses a value no user is identified by, as with_actor/2 does. A nil user id is a signed-out
  # visitor's session.
  @spec put_actor(Server.identity_id() | nil) :: :ok
  def put_actor(user_id) do
    Process.put(@actor_key, {:session, Server.validate_user_id!(user_id)})

    :ok
  end

  @doc """
  Returns true when the calling process is working for a session, signed in or not, or false when
  it is server code no request started.
  """
  @spec session?() :: boolean
  def session? do
    Process.get(@actor_key) != nil
  end

  @doc """
  Runs the given function with the given user id set as the calling process' actor and returns its result.
  A nil user id runs it as a signed-out visitor's session.
  The actor set before the call is restored afterwards, raised exceptions included, so nested calls compose.
  Raises Hologram.MisuseError for a value no user is identified by, before the function runs and with the
  actor left as it was - so no work runs as a user id like false, which the checks testing for an actor
  would read as none.
  """
  @spec with_actor(Server.identity_id() | nil, (-> any)) :: any
  def with_actor(user_id, fun) do
    Server.validate_user_id!(user_id)

    run_in_state({:session, user_id}, fun)
  end

  @doc """
  Runs the given function with no session, as server code no request started, and returns its
  result. The session set before the call is restored afterwards, raised exceptions included.
  """
  @spec without_session((-> any)) :: any
  def without_session(fun) do
    run_in_state(nil, fun)
  end

  defp put_state(nil), do: Process.delete(@actor_key)

  defp put_state(session), do: Process.put(@actor_key, session)

  defp run_in_state(state, fun) do
    previous_state = Process.get(@actor_key)
    put_state(state)

    try do
      fun.()
    after
      put_state(previous_state)
    end
  end
end
