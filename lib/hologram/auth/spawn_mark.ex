defmodule Hologram.Auth.SpawnMark do
  @moduledoc false

  # Marks the processes a session's process starts, so work moved off a request can be told from
  # server code no request started. The BEAM runs no code when a process starts, and a process
  # can't learn later what its starter was doing at that moment, since one connection process
  # serves many users in turn. What it does copy to a new process at spawn includes its trace
  # flags, so a process working for a session holds set_on_spawn in a trace session of its own.
  #
  # It also holds timestamp, which stays after the session ends, as the record that the process
  # has worked for one. A task a supervisor starts inherits nothing from its caller, so that record
  # is all it can read. It can't live in the process dictionary: Bandit clears that between the
  # requests of a keep-alive connection.
  #
  # The trace session has no event flags, so the tracer never receives a message, and being a
  # session of its own, it neither sees nor disturbs an app's own tracing.
  #
  # The flags live only as long as the tracer: killing it clears every process' flags, and setting
  # one afterwards still reports success. So a set is read back, and a session can't start
  # unmarked. Processes already running when that happens lose their mark, and what a request
  # already in flight starts afterwards, plain or through a supervisor, carries none. That's why
  # this process is supervised apart from the database unit, whose restarts would otherwise take it
  # down.

  use GenServer

  @mark_flag :set_on_spawn
  @served_flag :timestamp
  @session_key {__MODULE__, :trace_session}

  @doc """
  Starts the process that owns the trace session. A node has one, so a second start is ignored.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link([]) do
    case GenServer.start_link(__MODULE__, nil, name: __MODULE__) do
      {:error, {:already_started, _pid}} -> :ignore
      other -> other
    end
  end

  @doc """
  Returns true when the calling process holds the mark. An app with no data model runs no trace
  session, so nothing is marked there.
  """
  @spec marked?(:trace.session() | nil) :: boolean
  def marked?(session \\ trace_session())

  def marked?(nil), do: false

  def marked?(session) do
    {:flags, flags} = :trace.info(session, self(), :flags)

    @mark_flag in flags
  end

  @doc """
  Sets or clears the calling process' mark, which the processes it starts from then on inherit.
  Setting it also records for good that the process has worked for a session. Raises when the mark
  can't be set because the tracer has ended, so no session runs unmarked.
  """
  @spec put(boolean, :trace.session() | nil) :: :ok
  def put(marked?, session \\ trace_session())

  def put(_marked?, nil), do: :ok

  def put(marked?, session) do
    restore(marked?, session)

    if marked? and not marked?(session) do
      raise "can't mark this process as working for a session: #{inspect(__MODULE__)} isn't running"
    end

    :ok
  end

  @doc """
  Puts the calling process' mark back to what it was, without checking that it took, for leaving a
  session whose result must not be replaced by an error about the tracer.
  """
  @spec restore(boolean, :trace.session() | nil) :: :ok
  def restore(marked?, session \\ trace_session())

  def restore(_marked?, nil), do: :ok

  def restore(true, session) do
    :trace.process(session, self(), true, [@mark_flag, @served_flag])

    :ok
  end

  def restore(false, session) do
    :trace.process(session, self(), false, [@mark_flag])

    :ok
  end

  @doc """
  Returns true when the given local process has worked for a session, which includes having
  inherited the mark, or has ended. Read in one step, so a process leaving a session or ending
  can't be caught halfway. An app with no data model has no sessions to tell apart, so it's false
  there.
  """
  @spec served_or_ended?(pid, :trace.session() | nil) :: boolean
  def served_or_ended?(pid, session \\ trace_session())

  def served_or_ended?(_pid, nil), do: false

  def served_or_ended?(pid, session) do
    case :trace.info(session, pid, :flags) do
      {:flags, flags} -> @served_flag in flags
      :undefined -> true
    end
  end

  @doc """
  Drops the handle a previous start left behind when no tracer is running, for an app starting
  again with no data model or with Hologram not started, which runs no tracer and whose sessions
  have nothing to be marked for. Leaves a running tracer's handle in place.
  """
  @spec forget() :: :ok
  def forget do
    if Process.whereis(__MODULE__) == nil do
      :persistent_term.erase(@session_key)
    end

    :ok
  end

  # The handle stays in place when this process ends, however it ends, so that put/2 finds a dead
  # tracer and refuses until the restart replaces it, rather than finding no session and passing.
  @impl GenServer
  def init(nil) do
    session = :trace.session_create(__MODULE__, self(), [])
    :persistent_term.put(@session_key, session)

    {:ok, session}
  end

  defp trace_session do
    :persistent_term.get(@session_key, nil)
  end
end
