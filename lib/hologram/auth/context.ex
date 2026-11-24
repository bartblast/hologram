defmodule Hologram.Auth.Context do
  @moduledoc false

  # The session the current process is working for. Framework wrappers set it around the work they
  # run, and Hologram.Test.as_user/1,2 is the sanctioned test-only door.
  #
  # With a session, a process is doing a request's work, for the session's user or, with a nil user
  # id, for a signed-out visitor, whom the rules judge as an anonymous session. With no session, it
  # is server code outside Hologram's request handling, like a seed, a Mix task, a console, a worker
  # or an app's own plug or controller, and that is the trusted tier - unless a session's process
  # started it, as the paragraph after next says.
  #
  # The guarantee is about where identity comes from, not about what server code is able to
  # call: the actor always traces to an authenticated session, and nothing a client sends -
  # params, mutation args, envelopes - ever becomes it. Server code is trusted by
  # construction and can read and write past every policy by claiming trust, so
  # neither setter is a boundary against it. Shipping no act-as-user API keeps impersonation
  # off the app-facing surface, which is a surface decision, not an enforced one.
  #
  # The session is process-local and is not inherited, since a child can't tell which of the users
  # its starter serves in turn it was started for. So a process started for a session's work is
  # neither that user nor the trusted tier: session?/0 refuses it, until it carries the session
  # with capture/1 or its call claims trust. started_by_request?/0 says what can be told and what
  # can't: work handed to a process that was already running, like a call into a GenServer, still
  # has the server's authority. Framework code continuing a session's work in another process
  # re-establishes identity with with_actor/2.

  alias Hologram.Auth
  alias Hologram.Auth.SpawnMark
  alias Hologram.Server

  # Holds {:session, user_id}, so a signed-out visitor's nil user id is told from no session, or
  # :server inside without_session/1, which is no session by explicit choice.
  @actor_key {__MODULE__, :actor_user_id}

  # The search's answer, kept since how a process was started can't change, while what the search
  # can read about its ancestors does as they end or go on to serve a session.
  @started_by_request_key {__MODULE__, :started_by_request}

  @doc """
  Returns the user id of the actor set for the calling process, or nil for a signed-out visitor's
  session and when the process has no session. session?/0 tells those two apart.
  """
  @spec actor_user_id() :: Server.identity_id() | nil
  def actor_user_id do
    case Process.get(@actor_key) do
      {:session, user_id} -> user_id
      _no_session -> nil
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
    enter_state({:session, Server.validate_user_id!(user_id)})

    :ok
  end

  @doc """
  Returns true when the calling process is working for a session, signed in or not, or false when
  it is server code outside Hologram's request handling. Raises Hologram.MisuseError in a process
  started for a session's work that carries no session, which is neither (see
  started_by_request?/0).
  """
  @spec session?() :: boolean
  def session? do
    case Process.get(@actor_key) do
      {:session, _user_id} ->
        true

      :server ->
        false

      nil ->
        refuse_request_work!()
        false
    end
  end

  @doc """
  Returns the id of the user the calling process is working for, like actor_user_id/0, but raises
  Hologram.MisuseError in a process started for a session's work that carries no session, where
  nil would read as a signed-out visitor.
  """
  @spec user_id() :: Server.identity_id() | nil
  def user_id do
    session?()

    actor_user_id()
  end

  @doc """
  Returns true when the calling process, outside any session or without_session/1 of its own, was
  started for a session's work: by a process working for a session, or by a supervisor on behalf of
  a process that has served one, was itself started for one or has ended.

  A task a supervisor started carries only its caller's pid, and the caller may have moved on to
  other work, so a caller that has served a session counts even if it wasn't serving one then. An
  ended ancestor stops the search, so a process started by a supervised task that has ended isn't
  found. Neither is work handed to a process that was already running or that a supervisor started
  with no record of who asked for it, nor a stream's workers when its enumeration began outside the
  session. A process with the :sensitive flag, set before or during the session, passes on no mark,
  so what it spawns isn't found either, while a task it hands to a supervisor is still judged by
  its record.

  without_session/1 clears the mark for what the process spawns inside it, but a supervisor's task
  has no mark to clear: a task whose caller has served a session or has ended counts, even one
  handed over inside the block, and so does what such a task spawns inside the block. Both can
  claim trust. That includes a run_as_server job's run whose worker has ended, until the next
  worker kills it.
  """
  @spec started_by_request?() :: boolean
  def started_by_request? do
    cond do
      Process.get(@actor_key) != nil ->
        false

      SpawnMark.marked?() ->
        true

      true ->
        kept_search_answer()
    end
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
  Returns a function that runs the given one in the calling process' current state, whichever
  process calls it and whatever the calling process has moved on to by then. Backs
  Hologram.Auth.as_current_user/1. Takes a function of arity 0 or 1 and keeps its arity.
  """
  @spec capture((-> result)) :: (-> result) when result: any
  @spec capture((arg -> result)) :: (arg -> result) when arg: any, result: any
  def capture(fun) when is_function(fun, 0) do
    state = captured_state()

    fn -> run_in_state(state, fun) end
  end

  def capture(fun) when is_function(fun, 1) do
    state = captured_state()

    fn arg -> run_in_state(state, fn -> fun.(arg) end) end
  end

  def capture(other) do
    raise Hologram.MisuseError,
      message:
        "as_current_user takes a function of no arguments or of one, got: #{inspect(other)}"
  end

  @doc """
  Runs the given function with no session, as server code outside Hologram's request handling, and
  returns its result. The session set before the call is restored afterwards, raised exceptions
  included.
  """
  @spec without_session((-> any)) :: any
  def without_session(fun) do
    run_in_state(:server, fun)
  end

  # Work with no session to carry isn't handed the server's authority by wrapping it.
  defp captured_state do
    case Process.get(@actor_key) do
      {:session, _user_id} = session ->
        session

      :server ->
        :server

      nil ->
        refuse_request_work!()
        :server
    end
  end

  # The mark goes first: when it can't be set, the process is left as it was.
  defp enter_state({:session, _user_id} = session) do
    SpawnMark.put(true)
    Process.put(@actor_key, session)
  end

  defp enter_state(:server) do
    SpawnMark.put(false)
    Process.put(@actor_key, :server)
  end

  # A caller that spawned this process itself, directly or through plain spawns like the monitor
  # of Task.async_stream/3, passed on its mark at the spawn, and the walk goes on to its own
  # callers. So a plain Task from a process no request started isn't refused for having outlived
  # it. Only a real hand-off, through a process started with proc_lib like a supervisor, is judged,
  # and by the direct caller alone: one further up says nothing about a live caller that was
  # started by a process that has since ended.
  defp handed_over_by([caller | _callers], parent) do
    if not spawned_by?(parent, caller, []), do: caller
  end

  defp handed_over_by(_no_callers, _parent), do: nil

  defp kept_search_answer do
    case Process.get(@started_by_request_key) do
      nil ->
        answer = supervised_for_request?([self()], [])
        Process.put(@started_by_request_key, answer)

        answer

      answer ->
        answer
    end
  end

  defp put_state(nil), do: Process.delete(@actor_key)

  defp put_state(state), do: Process.put(@actor_key, state)

  # The mark is put back unchecked: a tracer that ended during the function mustn't replace its
  # result or its exception, and the next session this process enters refuses to start.
  defp run_in_state(state, fun) do
    previous_state = Process.get(@actor_key)
    previous_mark = SpawnMark.marked?()
    enter_state(state)

    try do
      fun.()
    after
      put_state(previous_state)
      SpawnMark.restore(previous_mark)
    end
  end

  defp refuse_request_work! do
    if started_by_request?() do
      raise Hologram.MisuseError,
        message:
          "this process was started for a request's work, so it has no user and isn't trusted server code. To run as the request's user, wrap the function it runs in Hologram.Auth.as_current_user/1, called in the request's process. To run as the server, with no user, claim trust, like query |> trust() |> DB.read(). A task from a Task.Supervisor also lands here when its caller has served a request, has run a wrapped function or has ended."
    end

    :ok
  end

  defp spawned_by?(caller, caller, _seen), do: true

  defp spawned_by?(pid, caller, seen) when is_pid(pid) and node(pid) == node() do
    with false <- pid in seen,
         [{:parent, parent}, {_ancestors_item, :undefined}] <-
           Process.info(pid, [:parent, {:dictionary, :"$ancestors"}]) do
      spawned_by?(parent, caller, [pid | seen])
    else
      _not_a_plain_spawn -> false
    end
  end

  defp spawned_by?(_pid, _caller, _seen), do: false

  # Goes up through the live ancestors. It never reads whether one is in a session or in
  # without_session/1: that says what the ancestor is doing now rather than when it started this
  # process, and the answer is kept, so a moment inside without_session/1 could clear request work
  # for good.
  #
  # One list of visited processes serves the whole search, since a process can be reached both as a
  # caller and as a parent, and walking it once per path takes exponential time on nested
  # supervisors. A caller is judged before that check, since being reached as a parent says nothing
  # about what it was doing as a caller.
  defp supervised_for_request?([], _seen), do: false

  defp supervised_for_request?([pid | pids], seen) do
    if node(pid) != node() or pid in seen do
      supervised_for_request?(pids, seen)
    else
      case Process.info(pid, [:parent, {:dictionary, :"$callers"}]) do
        nil ->
          supervised_for_request?(pids, [pid | seen])

        [{:parent, parent}, {_callers_item, callers}] ->
          caller = handed_over_by(callers, parent)

          (caller != nil and request_work?(caller)) or
            supervised_for_request?(Enum.filter([caller, parent], &is_pid/1) ++ pids, [pid | seen])
      end
    end
  end

  defp request_work?(pid) when node(pid) != node(), do: false

  defp request_work?(pid), do: SpawnMark.served_or_ended?(pid)
end
