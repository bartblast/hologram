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
  # it, which a pooled one cannot promise. It does not reconnect, because a session that ended took
  # its locks with it, and a worker carrying on would be running a job that looks abandoned to every
  # other node. Losing the connection ends this process, and the worker is restarted beside it. It
  # pings the server while idle, which is how a link that went dead is noticed rather than waited
  # on - once a call has been made, which arms the ping, and the worker makes one as it starts.

  @behaviour Postgrex.SimpleConnection

  alias Hologram.DB.Config
  alias Postgrex.SimpleConnection

  # Frozen for good, like the Migrator's key: nodes of two versions deriving different keys for one
  # job would miss each other's locks, and each would fail the jobs the other is running.
  @key_prefix "hologram_job_run:"

  # How long taking a lock may wait on the server. The claim takes it while holding the job's row,
  # so every other node claiming that row waits too - and gives up at the driver's 15 s query
  # timeout, failing its pass on every try. Bounded well under that: when the lock connection's
  # link goes silent, the call exits and the claim rolls back, which frees the row for the other
  # nodes as long as the pool still reaches the server. The worker crashes, and the one that
  # replaces it gives up whatever the server granted after all - once the lock connection answers,
  # or breaks and takes the lock with it, and until then this node runs nothing. Nothing between
  # the claim and the worker may catch the exit, or that lock would stay held under a queued row.
  @acquire_timeout_ms :timer.seconds(5)

  # Set once the connection is up rather than sent as startup parameters, which a session-mode
  # PgBouncer refuses unless told to ignore them.
  #
  # The ping already keeps the session from idling out, and the idle timeout is turned off in case
  # a server sets one lower than the ping - a session ended by it would free the lock of a run
  # still going. The keepalives bound how long the server keeps the session of a host that
  # vanished, and so its locks, to about a minute rather than the operating system's default of
  # hours.
  @session_settings """
  SET idle_session_timeout = 0;
  SET tcp_keepalives_idle = 30;
  SET tcp_keepalives_interval = 10;
  SET tcp_keepalives_count = 3
  """

  @doc """
  Takes the run lock of the job with the given id on the given connection, unless another session
  holds it. Returns whether it was taken.

  Never waits on another session: a lock another session holds is a run in progress, and nothing
  should wait on a run. Locks taken twice by one session stack, so each lock taken needs exactly
  one release.

  Exits when the server has not answered within 5 seconds, with the lock possibly taken.
  """
  @spec acquire(GenServer.server(), String.t()) :: boolean
  def acquire(connection, id) do
    [%Postgrex.Result{rows: [[taken]]}] =
      query!(connection, "SELECT pg_try_advisory_lock(#{key(id)})", @acquire_timeout_ms)

    taken == "t"
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
  ignored.
  """
  @spec release(GenServer.server(), String.t()) :: :ok
  def release(connection, id) do
    query!(connection, "SELECT pg_advisory_unlock(#{key(id)})")

    :ok
  end

  @doc """
  Gives up every run lock the given connection holds, and returns :ok.
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

  It returns without waiting on the server and connects right after, the way the listener does
  (see Hologram.DB.Config.listener_child_spec/1). A call made meanwhile waits for the connect, and
  a connect that fails ends the process.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    connection_opts =
      opts
      |> Config.connection_opts()
      |> Keyword.merge(auto_reconnect: false, sync_connect: false)

    SimpleConnection.start_link(__MODULE__, nil, connection_opts)
  end

  @impl SimpleConnection
  def handle_call({:query, statement}, from, state) do
    {:query, statement, %{state | from: from}}
  end

  @impl SimpleConnection
  def handle_connect(state) do
    {:query, @session_settings, %{state | from: nil}}
  end

  # The session settings are the only statement nobody waits on. Refused, they end the connection:
  # a session without them is the one a server can end under a run still going.
  @impl SimpleConnection
  def handle_result(%Postgrex.Error{} = error, %{from: nil}), do: raise(error)

  def handle_result(_results, %{from: nil} = state), do: {:noreply, state}

  def handle_result(results_or_error, state) do
    SimpleConnection.reply(state.from, results_or_error)

    {:noreply, %{state | from: nil}}
  end

  @impl SimpleConnection
  def init(_args), do: {:ok, %{from: nil}}

  @impl SimpleConnection
  def notify(_channel, _payload, _state), do: :ok

  # Waits as long as the server takes unless given a timeout: the server answers or the connection
  # breaks, which stops the connection process and exits the caller. A link that goes silent
  # mid-call is not pinged, so it breaks only when the operating system gives up retransmitting.
  # Only taking a lock is bounded (see @acquire_timeout_ms): a release comes after the claim's or
  # the outcome's transaction has ended, or before a worker runs anything, so no row waits on a
  # worker stuck there.
  defp query!(connection, statement, timeout \\ :infinity) do
    case SimpleConnection.call(connection, {:query, statement}, timeout) do
      %Postgrex.Error{} = error -> raise error
      results -> results
    end
  end
end
