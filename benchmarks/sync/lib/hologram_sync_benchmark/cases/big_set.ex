defmodule HologramSyncBenchmark.Cases.BigSet do
  @moduledoc false

  # credo:disable-for-this-file Credo.Check.Refactor.IoPuts

  # One write touching a row with a very big set, like linking a post to a tag with 300,000 posts.
  # For each batch, the dispatcher reads every pair of every row the batch touches, so this one
  # small write makes it read the tag's whole set. A session scans that set only when it drops the
  # row or is handed it, so the case also hides the tag from every client and shows it again.
  #
  # Nearly all the posts are hidden from the clients by their read rule. They hold the tag and a few
  # posts, so what's measured is the server reading the set rather than clients downloading it.

  use Hologram.DB

  alias Hologram.DB.Connection
  alias Hologram.DB.QueryCache
  alias Hologram.Sync.Live
  alias HologramSyncBenchmark.Client
  alias HologramSyncBenchmark.Clients
  alias HologramSyncBenchmark.Entities.SetPost
  alias HologramSyncBenchmark.Entities.SetTag
  alias HologramSyncBenchmark.Measure
  alias HologramSyncBenchmark.Peer
  alias HologramSyncBenchmark.Report
  alias HologramSyncBenchmark.Seed
  alias HologramSyncBenchmark.Seeding
  alias HologramSyncBenchmark.Step
  alias HologramSyncBenchmark.Sweep
  alias HologramSyncBenchmark.Writer

  @default_clients 100

  @default_sizes [30_000, 300_000]

  # How long a delivery may take before the step stops waiting and reports it as unfinished.
  @delivery_limit_ms 120_000

  @direct_reads 3

  @page "HologramSyncBenchmark.BigSetPage"

  @poll_ms 20

  # How many writes of each kind a size makes, and how many visible posts that takes: one for each
  # and one for the warm-up write.
  @timed_writes 3

  @visible_posts 2 * @timed_writes + 1

  @doc """
  Runs the case with the given options, writes its section into the README, and returns :ok.
  """
  @spec run(pid, keyword) :: :ok
  def run(conn, opts) do
    sizes = opts[:set_sizes] || @default_sizes
    count = hd(opts[:clients] || [@default_clients])
    memory_limit = opts[:memory_limit] * 1_073_741_824

    :ok = Clients.check_limits!(count, Step.connect_concurrency())
    :ok = Report.check_readme!()
    run_line = Report.run_line(conn)

    {results, stopped} = measure_all(conn, sizes, count, memory_limit, opts)

    # With nothing measured there's nothing to write, and writing would replace an earlier run's
    # good section with an empty one.
    if results == [] do
      raise "no set size was measured: #{inspect(stopped)}"
    end

    figure = figure(results, stopped, opts)
    IO.puts("Big set: #{figure}")

    Report.write_case!(
      "big_set",
      "One write touching a row with a big set",
      run_line,
      options(count, opts),
      figure,
      [{"Per set size", columns(), Enum.map(results, &row/1)}],
      figure_label: "A write into the set"
    )
  end

  @doc """
  Links the given post to the given tag and sets its title to the given value, in one write, and
  returns when it returned. Runs on the server node.
  """
  @spec link(String.t(), String.t(), String.t()) :: integer
  def link(post_id, tag_id, title) do
    SetPost
    |> filter(id == ^post_id)
    |> one()
    |> DB.read()
    |> put_attribute(:title, title)
    |> add_relationship(:tags, tag_id)
    |> DB.update!()

    :os.system_time(:microsecond)
  end

  @doc """
  Sets whether the given tag is hidden and its name, in one write, and returns when it returned.
  Runs on the server node.
  """
  @spec set_tag(String.t(), boolean, String.t()) :: integer
  def set_tag(tag_id, hidden, name) do
    SetTag
    |> filter(id == ^tag_id)
    |> one()
    |> DB.read()
    |> put_attribute(:hidden, hidden)
    |> put_attribute(:name, name)
    |> DB.update!()

    :os.system_time(:microsecond)
  end

  @doc """
  Times the read of every pair of the given tag, the read each batch touching the tag makes, and
  returns the median in milliseconds with the bytes it returned. Runs on the server node.
  """
  @spec read_figures(String.t()) :: map
  def read_figures(tag_id) do
    synced_types = QueryCache.synced_types()

    reads = for _read <- 1..@direct_reads, do: :timer.tc(fn -> read_set(tag_id, synced_types) end)

    {_micros, pairs} = hd(reads)

    read_ms =
      reads
      |> Enum.map(fn {micros, _pairs} -> micros / 1_000 end)
      |> Measure.percentile(50)

    bytes =
      pairs
      |> Map.values()
      |> Enum.sum_by(&byte_size/1)

    %{bytes: bytes, read_ms: read_ms}
  end

  defp read_set(tag_id, synced_types) do
    Connection.with_timeout(:infinity, fn ->
      Live.pairs_touching(%{SetTag => [tag_id]}, synced_types)
    end)
  end

  defp measure_all(conn, sizes, count, memory_limit, opts) do
    Sweep.over_sizes(
      sizes,
      &"Set of #{&1} posts",
      &measure_size(conn, {&1, &2}, count, memory_limit, opts),
      &summary/1
    )
  end

  # A failure at one size leaves the figures of the ones before it to be written.
  defp measure_size(conn, {size, first_marker}, count, memory_limit, opts) do
    {_seeding, seeded} =
      Seeding.seed!(conn, &Peer.rpc(&1, Seed, :big_set, [size, @visible_posts]))

    Sweep.with_guarded_peer(memory_limit, &measure(&1, seeded, {size, first_marker}, count, opts))
  catch
    kind, reason -> {:failed, Report.short_reason(kind, reason)}
  end

  defp measure(peer, seeded, {size, first_marker}, count, opts) do
    %{post_ids: [warm_up_post | post_ids], tag_id: tag_id} = seeded
    {ordinary_posts, linked_posts} = Enum.split(post_ids, @timed_writes)

    :ok = Peer.rpc(peer, Writer, :warm_up, [SetPost, warm_up_post, :title, "warm-up"])

    clients =
      peer
      |> Clients.base_opts(@page)
      |> Keyword.merge(cookie_path: "/session", count_type: inspect(SetTag))
      |> List.duplicate(count)
      |> Clients.start_all()

    try do
      :ok = Clients.fill!(clients, Step.connect_concurrency(), opts[:fill_timeout] * 1_000)

      direct = Peer.rpc(peer, __MODULE__, :read_figures, [tag_id])

      ordinary_ms =
        timed_writes(clients, ordinary_posts, first_marker, fn post_id, marker ->
          Peer.rpc(peer, Writer, :update, [SetPost, post_id, :title, marker])
        end)

      rise = Measure.start_memory_peak(peer)

      linked_ms =
        timed_writes(clients, linked_posts, first_marker + @timed_writes, fn post_id, marker ->
          Peer.rpc(peer, __MODULE__, :link, [post_id, tag_id, marker])
        end)

      rise_bytes = Measure.stop_memory_peak(rise)

      scan_rise = Measure.start_memory_peak(peer)
      dropped_ms = drop_tag_ms(peer, clients, tag_id)
      show_number = first_marker + 2 * @timed_writes
      shown_at = Peer.rpc(peer, __MODULE__, :set_tag, [tag_id, false, Client.marker(show_number)])
      shown_ms = Clients.delivery_ms(clients, show_number, shown_at, @delivery_limit_ms)
      scan_rise_bytes = Measure.stop_memory_peak(scan_rise)

      :ok = Peer.sync_log(peer)

      %{
        clients: count,
        direct: direct,
        dropped_ms: dropped_ms,
        heap_kills: Measure.heap_kills(peer.log_path),
        linked_ms: linked_ms,
        ordinary_ms: ordinary_ms,
        rise_bytes: rise_bytes,
        scan_rise_bytes: scan_rise_bytes,
        session_cuts: Measure.session_cuts(peer.log_path),
        shown_ms: shown_ms,
        size: size,
        streams_lost: Enum.count(clients, &Client.failed?/1)
      }
    after
      Clients.close_all(clients)
    end
  end

  # From hiding the tag to the last client told to drop it, or nil when one never was.
  defp drop_tag_ms(peer, clients, tag_id) do
    targets = Enum.map(clients, &{&1, Client.report(&1).counted.unsync + 1})
    committed_at = Peer.rpc(peer, __MODULE__, :set_tag, [tag_id, true, "hidden"])
    deadline = System.monotonic_time(:millisecond) + @delivery_limit_ms

    if await_drops(targets, deadline) do
      last_at =
        clients
        |> Enum.map(&Client.report(&1).counted_at.unsync)
        |> Enum.max()

      (last_at - committed_at) / 1_000
    end
  end

  # Waits on the others past a client that failed, so what's read next covers them too.
  defp await_drops(targets, deadline) do
    waiting =
      Enum.reject(targets, fn {client, target} ->
        Client.report(client).counted.unsync >= target
      end)

    cond do
      waiting == [] ->
        true

      Enum.all?(waiting, fn {client, _target} -> Client.failed?(client) end) ->
        false

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(@poll_ms)
        await_drops(waiting, deadline)
    end
  end

  # The median, of the writes that reached every client. Nil when none did.
  defp timed_writes(clients, post_ids, first_number, write) do
    post_ids
    |> Enum.with_index(first_number)
    |> Enum.map(fn {post_id, number} ->
      committed_at = write.(post_id, Client.marker(number))

      Clients.delivery_ms(clients, number, committed_at, @delivery_limit_ms)
    end)
    |> Enum.reject(&is_nil/1)
    |> Measure.percentile(50)
  end

  defp options(count, opts) do
    [
      "one tag with a set of hidden posts, plus #{@visible_posts} posts its #{count} anonymous " <>
        "clients may read, so they hold the tag and those few",
      "each size is seeded on its own and runs on a fresh server node",
      "#{@timed_writes} ordinary writes to a post outside the set, then #{@timed_writes} writes " <>
        "linking a post into it, each waited on for at most " <>
        "#{div(@delivery_limit_ms, 1_000)} s, and a dash means none reached every client in that " <>
        "time, or a client lost its stream first",
      "then the tag is hidden from every client and shown again, which has each session scan " <>
        "the whole set",
      "a run stops when the server node's memory passes #{opts[:memory_limit]} GB"
    ]
  end

  defp figure(results, stopped, opts) do
    last = List.last(results)

    text =
      "#{Report.cell(last.linked_ms)} ms to the last client with #{last.size} posts in the " <>
        "set, against #{Report.cell(last.ordinary_ms)} ms for a write outside it"

    case stopped do
      nil ->
        text

      %{reason: :memory, size: size} ->
        "#{text} (#{size} posts stopped at the #{opts[:memory_limit]} GB memory limit)"

      %{reason: message, size: size} ->
        "#{text} (#{size} posts failed: #{message})"
    end
  end

  defp summary(result) do
    "  direct read #{Report.cell(result.direct.read_ms)} ms, " <>
      "#{Report.cell(result.direct.bytes / 1_048_576)} MB, ordinary write " <>
      "#{Report.cell(result.ordinary_ms)} ms, write into the set " <>
      "#{Report.cell(result.linked_ms)} ms, memory rise " <>
      "#{Report.cell(result.rise_bytes / 1_048_576)} MB, tag dropped " <>
      "#{Report.cell(result.dropped_ms)} ms, handed back #{Report.cell(result.shown_ms)} ms, " <>
      "memory rise #{Report.cell(result.scan_rise_bytes / 1_048_576)} MB, " <>
      "#{result.streams_lost} streams lost, " <>
      "#{result.heap_kills} heap kills, #{result.session_cuts} sessions cut"
  end

  defp columns do
    [
      "Posts in the set",
      "Clients",
      "Read of the set ms, direct",
      "Set MB",
      "Write outside it ms",
      "Write into it ms",
      "Memory rise MB",
      "Tag dropped ms",
      "Tag handed back ms",
      "Drop and hand back memory rise MB",
      "Streams lost",
      "Heap kills",
      "Sessions cut"
    ]
  end

  defp row(result) do
    [
      result.size,
      result.clients,
      result.direct.read_ms,
      result.direct.bytes / 1_048_576,
      result.ordinary_ms,
      result.linked_ms,
      result.rise_bytes / 1_048_576,
      result.dropped_ms,
      result.shown_ms,
      result.scan_rise_bytes / 1_048_576,
      result.streams_lost,
      result.heap_kills,
      result.session_cuts
    ]
  end
end
