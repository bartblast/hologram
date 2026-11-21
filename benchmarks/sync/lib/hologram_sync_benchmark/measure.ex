defmodule HologramSyncBenchmark.Measure do
  @moduledoc false

  # What a step reads off the server node and turns into figures: CPU from scheduler samples,
  # memory, delivery times from the clients' reports.

  alias HologramSyncBenchmark.Peer

  @heap_kill_line "maximum heap size reached"

  # How a sync session cut for a stream that stopped taking its frames ended, in the server's log.
  @session_cut_line "(stop) :client_stalled"

  # How often the sessions holding a turn at the gate are read. Short, since a catch-up of a small
  # gap lasts tens of milliseconds, and only those few sessions are read each time.
  @turn_sample_ms 20

  # How many of those reads pass between two reads of the sessions waiting for a turn, about 250
  # ms, and how many of them are read: a wave can leave thousands waiting, and reading them all this
  # often would load the node being measured.
  @waiting_sample_every 12

  @waiting_sample_size 20

  # How long the sampler waits for the gate to answer before skipping that read.
  @gate_read_timeout_ms 1_000

  @type cpu_sample :: {integer, term}

  @type session_figures :: %{
          catching_up_each_bytes: non_neg_integer,
          catching_up_sum_bytes: non_neg_integer,
          error: String.t() | nil,
          gate_reads_missed: non_neg_integer,
          longest_mailbox: non_neg_integer,
          turns_ms: [non_neg_integer],
          waiting: non_neg_integer,
          waiting_each_bytes: non_neg_integer
        }

  @doc """
  Returns the CPU time the server node's schedulers were busy between the two samples, in
  milliseconds.

  Normal and dirty CPU schedulers count, each by its own utilization over the time between the
  samples. Dirty IO schedulers wait on IO rather than compute, so they're left out.

  A scheduler counts as busy while its thread runs work, including time the OS has the thread
  descheduled for another process, so on a machine whose cores the clients and Postgres share,
  this overstates the CPU the node used.
  """
  @spec cpu_ms(cpu_sample, cpu_sample) :: float
  def cpu_ms({_earlier_at, earlier} = earlier_sample, {_later_at, later} = later_sample) do
    elapsed_ms = elapsed_ms(earlier_sample, later_sample)

    busy =
      for {type, _id, utilization, _percent} <- :scheduler.utilization(earlier, later),
          type in [:normal, :cpu],
          reduce: 0.0 do
        sum -> sum + utilization
      end

    busy * elapsed_ms
  end

  @doc """
  Returns a sample of the server node's schedulers, for `cpu_ms/2`, with when it was taken.
  """
  @spec cpu_sample(Peer.t()) :: cpu_sample
  def cpu_sample(peer) do
    Peer.rpc(peer, __MODULE__, :sample_on_node, [])
  end

  @doc """
  Returns the milliseconds between the two samples, by the server node's clock.
  """
  @spec elapsed_ms(cpu_sample, cpu_sample) :: float
  def elapsed_ms({earlier_at, _earlier}, {later_at, _later}), do: (later_at - earlier_at) / 1_000

  @doc """
  Returns a sample of this node's schedulers with when it was taken, raising when scheduler wall
  time is off, since every sample would then read as idle. Runs on the server node.

  Taken and timed in one place, so the time between two samples is the node's own, with no
  call's round trip in it.
  """
  @spec sample_on_node :: cpu_sample
  def sample_on_node do
    if :erlang.statistics(:scheduler_wall_time) == :undefined do
      raise "scheduler wall time is off on the server node"
    end

    {System.monotonic_time(:microsecond), :scheduler.sample_all()}
  end

  @doc """
  Counts the processes the given log says were killed for their heap size.
  """
  @spec heap_kills(String.t()) :: non_neg_integer
  def heap_kills(log_path) do
    log_path
    |> File.stream!()
    |> Enum.count(&String.contains?(&1, @heap_kill_line))
  end

  @doc """
  Counts the sync sessions the given log says were cut for a stream that stopped taking frames.

  Counted from the log rather than from the clients: the server ends a cut session's stream, so
  the client sees a stream end like any other, and only the log says why.
  """
  @spec session_cuts(String.t()) :: non_neg_integer
  def session_cuts(log_path) do
    log_path
    |> File.stream!()
    |> Enum.count(&String.contains?(&1, @session_cut_line))
  end

  @doc """
  Returns how many of the given writes reached a client they shouldn't have, counted per client.

  `expected` names, for a write's number, the indexes of the reports that should have it. A
  marker anywhere else is a row a user wasn't allowed to read reaching that user's client.
  """
  @spec leaks(%{non_neg_integer => integer}, [map], (non_neg_integer -> [non_neg_integer])) ::
          non_neg_integer
  def leaks(writes, reports, expected) do
    indexed = Enum.with_index(reports)

    for {number, _committed_at} <- writes,
        allowed = allowed_indexes(expected, number),
        {report, index} <- indexed,
        not MapSet.member?(allowed, index),
        Map.has_key?(report.markers, number),
        reduce: 0 do
      count -> count + 1
    end
  end

  @doc """
  Returns the delivery times of the given writes, in milliseconds, and how many deliveries never
  came.

  `writes` maps a write's number to when it committed, and `expected` names, for a write's
  number, the indexes of the reports that should have it. Times are from the commit to the first
  arrival of the write's marker.
  """
  @spec latencies(%{non_neg_integer => integer}, [map], (non_neg_integer -> [non_neg_integer])) ::
          {[float], non_neg_integer}
  def latencies(writes, reports, expected) do
    reports = List.to_tuple(reports)

    for {number, committed_at} <- writes,
        index <- expected.(number),
        reduce: {[], 0} do
      {times, missing} ->
        case elem(reports, index).markers do
          %{^number => received_at} -> {[(received_at - committed_at) / 1_000 | times], missing}
          _absent -> {times, missing + 1}
        end
    end
  end

  defp allowed_indexes(expected, number) do
    number
    |> expected.()
    |> MapSet.new()
  end

  @doc """
  Starts guarding the server node's memory and returns the guard, for `stop_memory_guard/1`.

  A guard on the server node polls its total memory every 20 ms at high priority, so a burst of
  thousands of busy processes can't starve it. Past the given number of bytes it tells a watcher
  on this node, waits for the watcher's ack, then halts the node, so the notice is in before the
  node is gone. The watcher keeps the reading for `stop_memory_guard/1` to hand back.
  """
  @spec start_memory_guard(Peer.t(), pos_integer) :: pid
  def start_memory_guard(peer, limit) do
    caller = self()

    spawn(fn ->
      # A caller gone without stopping it leaves nobody to answer, so the watcher goes too.
      caller_ref = Process.monitor(caller)

      guard = Node.spawn(peer.node, __MODULE__, :guard_memory, [self(), limit])
      watch_memory(guard, %{caller: caller_ref, guard: Process.monitor(guard)}, nil)
    end)
  end

  @doc """
  Stops the given guard and returns the memory reading it stopped the server node at, nil when it
  didn't, or `:node_gone` when the node went down without the guard saying it stopped it.

  Waits for the guard to answer, so a node it halted just before is reported rather than missed.
  """
  @spec stop_memory_guard(pid) :: non_neg_integer | nil | :node_gone
  def stop_memory_guard(watcher) do
    ref = Process.monitor(watcher)
    send(watcher, {:stop, self()})

    receive do
      {:memory_guard, ^watcher, memory} ->
        Process.demonitor(ref, [:flush])
        memory

      {:DOWN, ^ref, :process, ^watcher, reason} ->
        raise "the memory guard's watcher went down: #{inspect(reason)}"
    end
  end

  @doc false
  # The guard, on the server node. Public only so the node can be told to run it.
  @spec guard_memory(pid, pos_integer) :: term
  def guard_memory(watcher, limit) do
    Process.flag(:priority, :high)

    poll_guard(watcher, limit)
  end

  defp poll_guard(watcher, limit) do
    receive do
      {:stop, ^watcher} -> send(watcher, {:guard_stopped, self()})
    after
      20 ->
        total = :erlang.memory(:total)

        if total > limit do
          send(watcher, {:memory_limit, self(), total})

          # Halted on the ack, or after a moment without one, since a node past the limit
          # mustn't keep growing because the driver is slow to answer.
          receive do
            {:ack, ^watcher} -> :ok
          after
            2_000 -> :ok
          end

          :erlang.halt()
        else
          poll_guard(watcher, limit)
        end
    end
  end

  # Only the caller's monitor is matched here: the guard's going down is left for await_guard/2,
  # which reports a node gone.
  defp watch_memory(guard, refs, stopped_at) do
    receive do
      {:memory_limit, ^guard, total} ->
        send(guard, {:ack, self()})
        watch_memory(guard, refs, total)

      {:stop, caller} ->
        send(caller, {:memory_guard, self(), stopped_at || await_guard(guard, refs.guard)})

      {:DOWN, ref, :process, _caller, _reason} when ref == refs.caller and stopped_at == nil ->
        send(guard, {:stop, self()})
    end
  end

  # The guard answers a stop, or a notice of the limit crossed in the meantime arrives first, or
  # the node is gone.
  defp await_guard(guard, ref) do
    send(guard, {:stop, self()})

    receive do
      {:guard_stopped, ^guard} ->
        nil

      {:memory_limit, ^guard, total} ->
        send(guard, {:ack, self()})
        total

      {:DOWN, ^ref, :process, ^guard, _reason} ->
        :node_gone
    end
  end

  @doc """
  Returns the server node's total memory in bytes.

  Collected first only when asked, before clients connect, for a baseline that holds no garbage.
  Never after: collecting every process, the streams' included, would change what happens next,
  since a stream's process is killed past a heap size (#1635), and no real server collects
  its streams on cue.
  """
  @spec memory(Peer.t(), keyword) :: non_neg_integer
  def memory(peer, opts \\ []) do
    if Keyword.get(opts, :collect, false) do
      Peer.rpc(peer, __MODULE__, :settled_memory, [])
    else
      Peer.rpc(peer, :erlang, :memory, [:total])
    end
  end

  @doc """
  Starts polling the server node's total memory every 20 ms and returns the poller, for
  `stop_memory_peak/1` to read from. The first reading is taken at once, before the call
  returns, as the baseline the peak is measured against.

  The poller runs on the server node itself, so its readings keep their pace when the node is
  saturated, which a poller calling in from the driver wouldn't. Not linked, so a server node
  that dies mid-step doesn't take the caller with it; the poller dies with the node.
  """
  @spec start_memory_peak(Peer.t()) :: pid
  def start_memory_peak(peer) do
    start = memory(peer)

    Node.spawn(peer.node, __MODULE__, :poll_memory, [self(), start, start])
  end

  @doc """
  Stops the given poller and returns how far above its first reading the server node's total
  memory rose at its highest, in bytes.
  """
  @spec stop_memory_peak(pid) :: non_neg_integer
  def stop_memory_peak(poller) do
    send(poller, {:stop, self()})

    receive do
      {:memory_peak, ^poller, peak} -> peak
    after
      10_000 -> raise "the memory poller on the server node didn't answer"
    end
  end

  @doc false
  # The poller's loop, on the server node. Public only so the node can be told to run it.
  @spec poll_memory(pid, non_neg_integer, non_neg_integer) :: :ok
  def poll_memory(owner, start, peak) do
    receive do
      {:stop, ^owner} ->
        send(owner, {:memory_peak, self(), peak - start})
        :ok
    after
      20 -> poll_memory(owner, start, max(peak, :erlang.memory(:total)))
    end
  end

  @doc """
  Starts reading the memory of the sync sessions at the server node's gate and returns the sampler,
  for `stop_session_sampler/1`. Runs on the server node, so it keeps its pace when the node is
  busy. It reads the gate's private state, copying the whole queue each time, which costs the node
  a few percent of a core with thousands waiting, so it's for a run measuring this rather than one
  measuring the wave's CPU.
  """
  @spec start_session_sampler(Peer.t()) :: pid
  def start_session_sampler(peer) do
    Node.spawn(peer.node, __MODULE__, :sample_sessions, [self()])
  end

  @doc """
  Stops the given sampler and returns the highest readings it took, or nil when the node went
  first.

  A session's bytes are its process memory, mailbox included, and the binaries it refers to, each
  counted once. The ones shared with other sessions count in each. `:catching_up_each_bytes` and
  `:waiting_each_bytes` are the most one session held in that state, `:catching_up_sum_bytes` the
  most the sessions holding a turn held together, `:waiting` the most waiting at once, and
  `:turns_ms` how long each turn seen ending lasted, to the sampler's 20 ms. A binary in a message
  still queued can be left out while the session is running.

  `:gate_reads_missed` counts the reads the gate was too busy to answer, and `:error` says why
  reading failed otherwise, such as a change to the gate's shape, keeping what was read before it.
  """
  @spec stop_session_sampler(pid) :: session_figures | nil
  def stop_session_sampler(sampler) do
    ref = Process.monitor(sampler)
    send(sampler, {:stop, self(), ref})

    receive do
      {^ref, figures} ->
        Process.demonitor(ref, [:flush])
        figures

      {:DOWN, ^ref, :process, ^sampler, _reason} ->
        nil
    end
  end

  @doc false
  # The sampler, on the server node. Public only so the node can be told to run it.
  @spec sample_sessions(pid) :: term
  def sample_sessions(owner) do
    Process.flag(:priority, :high)

    poll_sessions(Process.monitor(owner), 0, %{}, %{
      catching_up_each_bytes: 0,
      catching_up_sum_bytes: 0,
      error: nil,
      gate_reads_missed: 0,
      longest_mailbox: 0,
      turns_ms: [],
      waiting: 0,
      waiting_each_bytes: 0
    })
  end

  defp poll_sessions(owner_ref, tick, holding, figures) do
    receive do
      {:stop, from, ref} ->
        send(from, {ref, figures})

      {:DOWN, ^owner_ref, :process, _owner, _reason} ->
        :ok
    after
      @turn_sample_ms ->
        {holding, figures} = read_gate(tick, holding, figures)

        poll_sessions(owner_ref, tick + 1, holding, figures)
    end
  end

  defp read_gate(tick, holding, figures) do
    gate = :sys.get_state(Hologram.Sync.Gate, @gate_read_timeout_ms)
    {holding, figures} = read_turns(gate, holding, figures)

    if rem(tick, @waiting_sample_every) == 0 do
      {holding, read_waiting(gate, figures)}
    else
      {holding, figures}
    end
  catch
    :exit, {:timeout, _call} ->
      {holding, %{figures | gate_reads_missed: figures.gate_reads_missed + 1}}

    kind, reason ->
      {holding, %{figures | error: figures.error || Exception.format_banner(kind, reason)}}
  end

  defp read_turns(gate, holding, figures) do
    now = System.monotonic_time(:millisecond)
    holders = Map.keys(gate.holders)
    {still_holding, ended} = Map.split(holding, holders)

    turns_ms = Enum.map(ended, fn {_pid, since} -> now - since end)

    read =
      holders
      |> Enum.map(&session_memory/1)
      |> Enum.reject(&is_nil/1)

    figures = %{
      figures
      | catching_up_each_bytes:
          Enum.max([figures.catching_up_each_bytes | Enum.map(read, &elem(&1, 0))]),
        catching_up_sum_bytes:
          max(figures.catching_up_sum_bytes, Enum.sum_by(read, &elem(&1, 0))),
        longest_mailbox: Enum.max([figures.longest_mailbox | Enum.map(read, &elem(&1, 1))]),
        turns_ms: turns_ms ++ figures.turns_ms
    }

    # A session already holding keeps the moment it was first seen.
    holding =
      holders
      |> Map.new(&{&1, now})
      |> Map.merge(still_holding)

    {holding, figures}
  end

  defp read_waiting(gate, figures) do
    waiting =
      gate.queue
      |> :queue.to_list()
      |> Enum.filter(fn {_pid, ref} -> MapSet.member?(gate.waiting, ref) end)

    read =
      waiting
      |> Enum.take(@waiting_sample_size)
      |> Enum.map(fn {pid, _ref} -> session_memory(pid) end)
      |> Enum.reject(&is_nil/1)

    %{
      figures
      | waiting: max(figures.waiting, length(waiting)),
        waiting_each_bytes: Enum.max([figures.waiting_each_bytes | Enum.map(read, &elem(&1, 0))])
    }
  end

  # Nil for a session that has ended since the gate was read.
  defp session_memory(pid) do
    case Process.info(pid, [:binary, :memory, :message_queue_len]) do
      nil ->
        nil

      info ->
        binaries =
          info[:binary]
          |> Enum.uniq_by(fn {address, _size, _references} -> address end)
          |> Enum.sum_by(fn {_address, size, _references} -> size end)

        {info[:memory] + binaries, info[:message_queue_len]}
    end
  end

  @doc """
  Returns the value at the given percentile of the given numbers, nearest rank, or nil for none.
  """
  @spec percentile([number], number) :: number | nil
  def percentile([], _percent), do: nil

  def percentile(values, percent) do
    sorted = Enum.sort(values)
    rank = max(ceil(percent / 100 * length(sorted)), 1)

    Enum.at(sorted, rank - 1)
  end

  @doc """
  Collects garbage in every process and returns the node's total memory in bytes. Runs on the
  server node.
  """
  @spec settled_memory :: non_neg_integer
  def settled_memory do
    Enum.each(Process.list(), &:erlang.garbage_collect/1)

    :erlang.memory(:total)
  end

  @doc """
  Turns on scheduler wall time, tells the given process it's on, and holds it on for as long as
  the calling process lives, which never returns. Runs on the server node, in a process of its
  own.

  The flag counts per process that turned it on and goes off when the last of them exits, so
  turning it on from a call would leave it on only for that call.
  """
  @spec hold_scheduler_wall_time(pid) :: no_return
  def hold_scheduler_wall_time(owner) do
    :erlang.system_flag(:scheduler_wall_time, true)
    send(owner, {:scheduler_wall_time_on, self()})

    hold()
  end

  defp hold do
    receive do
      :never -> hold()
    end
  end
end
