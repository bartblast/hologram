defmodule Hologram.Auth.SpawnMark do
  @moduledoc false

  # Marks the processes a session's process starts, so work moved off a request can be told from
  # server code no request started. The BEAM runs no code when a process starts, and a process
  # can't learn later what its starter was doing at that moment, since one connection process
  # serves many users in turn. The one thing it copies to a new process at spawn is its trace
  # flags, so a process working for a session holds set_on_spawn in a trace session of its own.
  #
  # The trace session has no event flags, so the tracer never receives a message, and being a
  # session of its own, it neither sees nor disturbs an app's own tracing.
  #
  # The flags live only as long as the tracer: killing it clears every process' flags, and setting
  # one afterwards still reports success. So a set is read back, and a session can't start
  # unmarked. Processes already running when that happens lose their mark.

  use GenServer

  @flags [:set_on_spawn]
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

    :set_on_spawn in flags
  end

  @doc """
  Sets or clears the calling process' mark, which the processes it starts from then on inherit.
  Raises when the mark can't be set because the tracer has ended, so no session runs unmarked.
  """
  @spec put(boolean, :trace.session() | nil) :: :ok
  def put(marked?, session \\ trace_session())

  def put(_marked?, nil), do: :ok

  def put(marked?, session) do
    :trace.process(session, self(), marked?, @flags)

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

  def restore(marked?, session) do
    :trace.process(session, self(), marked?, @flags)

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
