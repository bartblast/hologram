defmodule Hologram.Job.RunLock do
  @moduledoc false

  # The connection a worker holds its run locks on: one session-level advisory lock per job it is
  # running, named by the job's id, taken as the job is claimed and given up once its outcome is
  # recorded. A running row whose lock any session can take has nobody running it.
  #
  # Session-scoped rather than transactional because a run spans three transactions and reaches
  # outside the database between them, and because PostgreSQL frees a session lock when the
  # session ends - so a node that stops, a worker that crashes and a connection that drops all free
  # it, with no process left to do so.
  #
  # A connection of its own, outside the pool: a session lock stays with the connection that took
  # it, which a pooled one cannot promise. Held for as long as its session lasts (see
  # Hologram.DB.Config.held_connection_opts/1): while the database refuses connections it keeps
  # trying, and the worker waits for it in await_connected/1 before anything else. It does not
  # reconnect a session it had, because a session that ended took its locks with it, and a worker
  # carrying on would be running a job that looks abandoned to every other node. Losing the session
  # ends this process, and the worker is restarted beside it. It pings the server while idle, and
  # it ends itself when the server leaves a statement unanswered - a call's or the session
  # settings' - which is how a link that went dead is noticed rather than waited on.

  @behaviour Postgrex.SimpleConnection

  alias Hologram.DB
  alias Hologram.DB.Config
  alias Postgrex.SimpleConnection

  # Frozen for good, like the Migrator's key: nodes of two versions deriving different keys for one
  # job would miss each other's locks, and each would fail the jobs the other is running.
  @key_prefix "hologram_job_run:"

  # How long a call's statement may wait on the server before the connection is ended. A statement
  # left waiting on a link gone silent would otherwise wait until the operating system gives up
  # retransmitting - about 15 minutes on Linux - with every run's lock call stuck behind it. A
  # silent link isn't pinged while a statement is in flight, and TCP keepalives only probe a
  # connection with nothing in flight, so the bound is what notices it. The idle ping's wait for
  # its answer gets the same bound (see start_link/1), since a call arriving while a ping is in
  # flight waits for it.
  #
  # Ending the connection rather than only giving up the call, because the session's state is
  # unknown once its answer is missing: a lock may have been taken or given up after all. Killed,
  # the connection takes the worker and every run with it, new ones replace them, and the server
  # frees the old session's locks once it finds the peer gone - within about a minute (see
  # @session_settings).
  #
  # Measured by the connection from when it sends the statement, not by the caller from when it
  # calls. The connection runs one statement at a time, and jobs running at once queue their calls
  # behind each other on it - a caller's bound would count the wait in that queue, and calls queued
  # behind a slow one would share it, so one slow statement the server still answers would end the
  # session every run on this node holds its lock on. Each statement gets the whole bound instead.
  #
  # Taking a lock is the call this matters most for. The claim takes it while holding the job's row,
  # so every other node claiming that row waits too - and gives up at the driver's 15 s query
  # timeout, failing its claim on every try. A claim's call waits for the statements queued ahead of
  # it as well as its own, which on a healthy link is up to a round trip for each run in flight, far
  # under that. A link gone silent ends the connection within the bound of the statement in flight,
  # and every call queued behind it exits with it, which rolls the claim back and frees the row for
  # the other nodes as long as the pool still reaches the server. Only a server answering each
  # statement just under the bound could hold a claim past 15 s, which is accepted.
  @call_timeout_ms :timer.seconds(5)

  # Set once the connection is up rather than sent as startup parameters, which a session-mode
  # PgBouncer refuses unless told to ignore them.
  #
  # The ping already keeps the session from idling out, and the idle timeout is turned off in case
  # a server sets one lower than the ping - a session ended by it would free the lock of a run
  # still going. The keepalives and the user timeout bound how long the server keeps the session of
  # a host that vanished, and so its locks, to about a minute rather than the operating system's
  # default: the keepalives when the server has nothing unacknowledged (hours otherwise), the user
  # timeout when it does - an answer sent as the link went silent - which the keepalives never probe
  # (about 15 minutes otherwise). A server whose platform has no user timeout keeps it at 0, and
  # logs that it is not supported on each connect. They bound only a direct connection: behind a
  # pooler or a proxy the server's peer is the pooler, whose own keepalives toward the node bound
  # how long the session and its locks live.
  @session_settings """
  SET idle_session_timeout = 0;
  SET tcp_keepalives_idle = 30;
  SET tcp_keepalives_interval = 10;
  SET tcp_keepalives_count = 3;
  SET tcp_user_timeout = 60000
  """

  @doc """
  Takes the run lock of the job with the given id on the given connection, unless another session
  holds it. Returns whether it was taken.

  Never waits on another session: a lock another session holds is a run in progress, and nothing
  should wait on a run. Locks taken twice by one session stack, so each lock taken needs exactly
  one release.

  Exits when the server leaves the statement unanswered for 5 seconds from when the connection
  sends it, with the lock possibly taken, since the connection ends itself then - like release/2
  and release_all/1, and like every call waiting behind it. Raises when the connection has no
  session yet (see await_connected/1), like them too.
  """
  @spec acquire(GenServer.server(), String.t()) :: boolean
  def acquire(connection, id) do
    [%Postgrex.Result{rows: [[taken]]}] =
      query!(connection, "SELECT pg_try_advisory_lock(#{key(id)})")

    taken == "t"
  end

  @doc """
  Returns :ok once the connection has a session with its settings applied - at once when it has
  one already.

  Waits as long as the database refuses connections. Every other call made before then fails, so
  the worker makes this one first. Exits if the connection ends first - when the server refuses
  the session settings, leaves them unanswered for 150 seconds, or the session is lost before they
  are applied.
  """
  @spec await_connected(GenServer.server()) :: :ok
  def await_connected(connection) do
    SimpleConnection.call(connection, :await_connected, :infinity)
  end

  @doc """
  Returns the child spec of the connection, started with the given options (see start_link/1).
  """
  @spec child_spec(keyword) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: Keyword.get(opts, :name, __MODULE__), start: {__MODULE__, :start_link, [opts]}}
  end

  @doc """
  Returns the advisory lock key the run lock of the job with the given id is named by.

  A key in PostgreSQL's single-key space rather than the two-key one Hologram.DB.SetLock names row
  locks in, where a lock held for a whole run would stop writes entering a set the job's row owns.
  The single-key space holds the Migrator's and the schema reconciler's fixed keys, which a job's
  key matches only by hash chance.
  """
  @spec key(String.t()) :: integer
  def key(id) do
    <<key::signed-integer-size(64), _rest::binary>> = :crypto.hash(:sha256, @key_prefix <> id)

    key
  end

  @doc """
  Gives up the run lock of the job with the given id on the given connection, and returns :ok.

  A lock the session does not hold is left as it is - PostgreSQL answers with a warning, which is
  ignored. Raises when the connection has no session yet (see await_connected/1), and exits when
  the server leaves the statement unanswered for 5 seconds, which ends the connection.
  """
  @spec release(GenServer.server(), String.t()) :: :ok
  def release(connection, id) do
    query!(connection, "SELECT pg_advisory_unlock(#{key(id)})")

    :ok
  end

  @doc """
  Gives up every run lock the given connection holds, and returns :ok.

  Raises when the connection has no session yet (see await_connected/1), and exits when the server
  leaves the statement unanswered for 5 seconds, which ends the connection.
  """
  @spec release_all(GenServer.server()) :: :ok
  def release_all(connection) do
    query!(connection, "SELECT pg_advisory_unlock_all()")

    :ok
  end

  @doc """
  Starts the connection, linked to the caller.

  `:name` registers it. Every other option overrides the configured database's connection options,
  which is how a connection reaches another database on the same server - advisory locks are per
  database, so the connection must reach the one the jobs are in.

  It returns without waiting on the server, and keeps trying to connect while the database
  refuses it (see Hologram.DB.Config.held_connection_opts/1, which the options also override).
  The idle ping's wait for its answer is bounded like a call's statement, unless the options give
  a `:ping_timeout`.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    connection_opts =
      opts
      |> Keyword.put_new(:ping_timeout, @call_timeout_ms)
      |> Config.held_connection_opts()

    # TODO(#1696): SimpleConnection.start_link/3 again, see Hologram.DB.SimpleConnection.
    DB.SimpleConnection.start_link(__MODULE__, nil, connection_opts)
  end

  @impl SimpleConnection
  def handle_call(:await_connected, from, %{connected: true} = state) do
    SimpleConnection.reply(from, :ok)

    {:noreply, state}
  end

  def handle_call(:await_connected, from, state) do
    {:noreply, %{state | waiting: [from | state.waiting]}}
  end

  # Bounded from here, as the statement goes out, so a call queued behind others gets the whole
  # bound for its own statement (see @call_timeout_ms). SimpleConnection sends the statement and
  # waits for its answer inside this process, so the kill is what ends a wait the server leaves
  # unanswered: the caller and every call queued behind it exit on the connection's DOWN.
  def handle_call({:query, statement}, from, %{connected: true} = state) do
    {:ok, timer} = :timer.kill_after(state.call_timeout_ms)

    {:query, statement, %{state | from: from, timer: timer}}
  end

  # Without a session there is no socket to send the statement on. Failed in the caller rather than
  # here, so a caller that did not wait (see await_connected/1) does not take the connection down.
  def handle_call({:query, _statement}, from, state) do
    SimpleConnection.reply(from, %Postgrex.Error{
      message: "the run lock connection has no session yet, see await_connected/1"
    })

    {:noreply, state}
  end

  # SimpleConnection keeps the idle ping off after a connect (it drops what handle_connect/1
  # returns), so without the message below a session nobody calls would never be pinged.
  #
  # The settings are bounded by a kill (see Hologram.DB.Config.first_statement_timeout_ms/0), since
  # nobody waiting on the session gives up (see await_connected/1): a link that went silent as the
  # session opened would leave the worker waiting. Killed, the connection takes the worker with it,
  # and a new one replaces both. The waits while the database refuses connections stay unbounded.
  @impl SimpleConnection
  def handle_connect(state) do
    send(self(), :arm_ping)

    {:ok, timer} = :timer.kill_after(state.setup_timeout_ms)

    {:query, @session_settings, %{state | from: nil, timer: timer}}
  end

  @impl SimpleConnection
  @spec handle_disconnect(map) :: no_return
  def handle_disconnect(state) do
    disarm(state)
    Config.end_lost_session!()
  end

  # :arm_ping, and anything else - the connection traps exits.
  @impl SimpleConnection
  def handle_info(_message, state), do: {:noreply, state}

  # The session settings are the only statement nobody waits on. Refused, they end the connection:
  # a session without them is the one a server can end under a run still going.
  @impl SimpleConnection
  def handle_result(%Postgrex.Error{} = error, %{from: nil} = state) do
    disarm(state)
    raise error
  end

  # The session is usable once its settings are applied, not as soon as it opens.
  def handle_result(_results, %{from: nil} = state) do
    state = disarm(state)

    state.waiting
    |> Enum.reverse()
    |> Enum.each(&SimpleConnection.reply(&1, :ok))

    {:noreply, %{state | connected: true, waiting: []}}
  end

  def handle_result(results_or_error, state) do
    state = disarm(state)

    SimpleConnection.reply(state.from, results_or_error)

    {:noreply, %{state | from: nil}}
  end

  # The timeouts live in the state so that a test can shorten them.
  @impl SimpleConnection
  def init(_args) do
    {:ok,
     %{
       call_timeout_ms: @call_timeout_ms,
       connected: false,
       from: nil,
       setup_timeout_ms: Config.first_statement_timeout_ms(),
       timer: nil,
       waiting: []
     }}
  end

  @impl SimpleConnection
  def notify(_channel, _payload, _state), do: :ok

  # A kill that fired just before the cancel reaches this process before the cancel returns, since
  # the timer server sends it, so this process never carries on with one pending.
  defp disarm(%{timer: nil} = state), do: state

  defp disarm(state) do
    :timer.cancel(state.timer)

    %{state | timer: nil}
  end

  # Raises at once when the connection has no session yet (see await_connected/1). Otherwise waits
  # for the server's answer with no bound of its own: the connection bounds the statement once it
  # sends it, and ends itself when the server leaves it unanswered (see handle_call/3), which exits
  # the caller. A connection that breaks meanwhile stops, which exits the caller too.
  #
  # The caller exits only once the connection is gone, on its DOWN, so a rest_for_one supervisor
  # counts one restart for a statement left unanswered rather than two: a dying process sends its
  # link exits before its monitor DOWNs, so the supervisor already has the connection's exit when
  # the caller gets the DOWN. That is how the runtime works rather than a documented guarantee, and
  # getting it wrong costs one restart more, still within the limit.
  defp query!(connection, statement) do
    case SimpleConnection.call(connection, {:query, statement}, :infinity) do
      %Postgrex.Error{} = error -> raise error
      results -> results
    end
  end
end
