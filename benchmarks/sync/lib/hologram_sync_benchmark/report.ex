defmodule HologramSyncBenchmark.Report do
  @moduledoc false

  # Writes a case's figures into the README's results, replacing what an earlier run of the same
  # case wrote and leaving the other cases' sections as they were, so cases can be run one at a
  # time. Each section says where its figures come from: the commit, the machine, the database
  # and the options, since a figure means nothing without them.

  alias HologramSyncBenchmark.Measure

  @case_order ~w(board board_roles tenants access deploy deploy_tenants lock)

  @readme_path "README.md"

  @results_end "<!-- /results -->"

  @results_start "<!-- results -->"

  @doc """
  Raises when the README has nowhere to write results, and returns :ok.

  For the start of a case, before it runs: a sweep can take an hour, and finding no markers
  only once it's over would lose its figures.
  """
  @spec check_readme! :: :ok
  def check_readme! do
    readme = File.read!(@readme_path)

    for marker <- [@results_start, @results_end], not String.contains?(readme, marker) do
      raise "#{@readme_path} has no #{marker} line to write the results at"
    end

    :ok
  end

  @doc """
  Returns the line saying where a run's figures come from: when it started, the commit, the
  machine, the database and Elixir.

  Read when a run starts, so a commit or an edit made while it runs isn't credited with its
  figures.
  """
  @spec run_line(pid) :: String.t()
  def run_line(conn) do
    date = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M UTC")

    "Run #{date} on #{git_line()}, #{machine_line()}, #{postgres_line(conn)}, " <>
      "Elixir #{System.version()} on OTP #{:erlang.system_info(:otp_release)}."
  end

  @doc """
  Writes the given case's section into the README and returns :ok.

  `run_line` is `run_line/1` read when the run started, `options` the lines describing what the
  run was given, and `figure` the case's clients-per-node figure, or whatever the case concludes
  under `:figure_label`. `tables` are `{heading, columns, rows}`, each row a list of cells.
  """
  @spec write_case!(
          String.t(),
          String.t(),
          String.t(),
          [String.t()],
          String.t(),
          [{String.t(), [String.t()], [[term]]}],
          keyword
        ) :: :ok
  def write_case!(name, title, run_line, options, figure, tables, opts \\ []) do
    :ok = check_readme!()

    section = """
    <!-- case:#{name} -->
    ### #{title}

    #{run_line}

    #{Enum.map_join(options, "\n", &("- " <> &1))}

    #{Keyword.get(opts, :figure_label, "Clients per node")}: **#{figure}**

    #{Enum.map_join(tables, "\n", &table/1)}<!-- /case:#{name} -->
    """

    readme = File.read!(@readme_path)
    [head, rest] = String.split(readme, @results_start, parts: 2)
    [old_results, tail] = String.split(rest, @results_end, parts: 2)

    new_results = put_section(old_results, name, section)

    File.write!(@readme_path, head <> @results_start <> new_results <> @results_end <> tail)
  end

  @doc """
  Formats a figure for a table cell: integers as they are, floats with fewer decimals the larger
  they are, so a small one keeps its digits, and a missing figure as a dash.
  """
  @spec cell(term) :: String.t()
  def cell(nil), do: "-"

  def cell(value) when is_float(value) and abs(value) >= 100,
    do: :erlang.float_to_binary(value, decimals: 0)

  def cell(value) when is_float(value) and abs(value) >= 10,
    do: :erlang.float_to_binary(value, decimals: 1)

  def cell(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)

  def cell(value), do: to_string(value)

  @doc """
  Returns the given step's fill figures as a table row.

  None of the database's counters: a fill is short against the settle around it, so the idle
  rate taken off swamps what the fill did, rows scanned included, and the figures come out as
  noise, negative ones too. A refill of many clients at once is big enough to show (see the
  deploy case).
  """
  @spec fill_row(map) :: [term]
  def fill_row(result) do
    %{fill: fill} = result

    [
      result.clients,
      "#{fill.filled}/#{result.clients}",
      Measure.percentile(fill.ms, 50),
      Measure.percentile(fill.ms, 99),
      fill.restarts,
      result.heap_kills,
      fill.cpu_ms,
      result.memory_per_client && result.memory_per_client / 1_024
    ]
  end

  @doc """
  The columns of `fill_row/1`.
  """
  @spec fill_columns :: [String.t()]
  def fill_columns do
    [
      "Clients",
      "Filled",
      "Fill p50 ms",
      "Fill p99 ms",
      "Fills restarted",
      "Heap kills",
      "Server CPU ms",
      "KB per client"
    ]
  end

  @doc """
  Returns the given step's single write figures as a table row.
  """
  @spec isolated_row(map) :: [term]
  def isolated_row(result) do
    [
      result.clients,
      result.isolated.last_delivery_ms,
      result.isolated.cpu_ms,
      result.isolated.cut_short
    ]
  end

  @doc """
  The columns of `isolated_row/1`.
  """
  @spec isolated_columns :: [String.t()]
  def isolated_columns do
    ["Clients", "To the last client ms", "Server CPU ms", "Cut short"]
  end

  @doc """
  Returns the given step's steady write figures as a table row.
  """
  @spec steady_row(map) :: [term]
  def steady_row(result) do
    %{steady: steady} = result

    # Per-write figures over writes some sessions stopped working on partway cover less work than
    # the writes caused, so they read as cheaper writes than these were, and are left out.
    complete? = steady.missing == 0 and steady.streams_lost == 0 and result.session_cuts == 0
    per_write = fn value -> if complete?, do: value end

    [
      result.clients,
      steady.rate,
      "#{steady.deliveries}/#{steady.deliveries + steady.missing}",
      steady.p50_ms,
      steady.p95_ms,
      steady.p99_ms,
      steady.max_ms,
      steady.leaked,
      steady.streams_lost,
      result.session_cuts,
      per_write.(steady.cpu_ms_per_write),
      per_write.(steady.cpu_ms_per_write / result.clients),
      per_write.(steady.db.xact_commit),
      per_write.(steady.db.tup_returned),
      per_write.(steady.db.tup_fetched),
      per_write.(steady.db.active_ms),
      passed_cell(result)
    ]
  end

  @doc """
  The columns of `steady_row/1`.
  """
  @spec steady_columns :: [String.t()]
  def steady_columns do
    [
      "Clients",
      "Writes/s",
      "Delivered",
      "p50 ms",
      "p95 ms",
      "p99 ms",
      "Max ms",
      "Leaked",
      "Streams lost",
      "Sessions cut",
      "CPU ms per write",
      "CPU ms per write per client",
      "DB commits per write",
      "DB rows scanned per write",
      "DB rows fetched per write",
      "DB ms per write",
      "Step passed"
    ]
  end

  @doc """
  Returns the "Step passed" cell for the given result, saying when autovacuum ran during the
  step, which puts its work into the step's database figures.
  """
  @spec passed_cell(map) :: String.t()
  def passed_cell(result) do
    passed = if result.passed, do: "yes", else: "no"

    if result.autovacuum_ran, do: passed <> ", autovacuum ran", else: passed
  end

  # Standard output only, so a warning on standard error can't pass for the answer, and in the C
  # locale, so a number prints with a decimal point whatever the machine's language.
  defp command(command, args) do
    case System.cmd(command, args, env: [{"LC_ALL", "C"}], stderr_to_stdout: false) do
      {output, 0} -> String.trim(output)
      _failed -> nil
    end
  rescue
    ErlangError -> nil
  end

  # Changes to the benchmark itself don't make the figures another tree's.
  defp git_line do
    commit = command("git", ["rev-parse", "--short", "HEAD"])
    status = command("git", ["status", "--porcelain", "--", "../..", ":(exclude)."])

    case {commit, status} do
      {nil, _status} -> "an unknown commit"
      {commit, nil} -> "commit #{commit}, tree state unknown"
      {commit, ""} -> "commit #{commit}"
      {commit, _changes} -> "commit #{commit} with uncommitted changes"
    end
  end

  defp linux_machine do
    cpu =
      with {:ok, cpuinfo} <- File.read("/proc/cpuinfo"),
           [_all, model] <- Regex.run(~r/^model name\s*:\s*(.+)$/m, cpuinfo) do
        model
      else
        _unknown -> nil
      end

    memory_bytes =
      with {:ok, meminfo} <- File.read("/proc/meminfo"),
           [_all, kilobytes] <- Regex.run(~r/^MemTotal:\s*(\d+) kB$/m, meminfo) do
        Integer.to_string(String.to_integer(kilobytes) * 1_024)
      else
        _unknown -> nil
      end

    {cpu, memory_bytes, command("uname", ["-sr"])}
  end

  defp machine_line do
    cores = :erlang.system_info(:logical_processors)

    {cpu, memory_bytes, os} =
      case :os.type() do
        {:unix, :darwin} -> macos_machine()
        _other -> linux_machine()
      end

    memory =
      case memory_bytes && Integer.parse(memory_bytes) do
        {bytes, ""} -> "#{div(bytes, 1_073_741_824)} GB"
        _unknown -> "unknown memory"
      end

    "#{cpu || "unknown CPU"}, #{cores} cores, #{memory}, #{os || "unknown OS"}, " <>
      "load average #{load_average() || "unknown"} when the run started"
  end

  # The 1-minute load average, so figures taken while other work kept the machine busy say so.
  defp load_average do
    text =
      case :os.type() do
        {:unix, :darwin} -> command("sysctl", ["-n", "vm.loadavg"])
        _other -> read_file("/proc/loadavg")
      end

    case text && Regex.run(~r/\d+(?:\.\d+)?/, text) do
      [one_minute] -> one_minute
      _unknown -> nil
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, text} -> text
      {:error, _reason} -> nil
    end
  end

  defp macos_machine do
    os =
      case command("sw_vers", ["-productVersion"]) do
        nil -> nil
        version -> "macOS #{version}"
      end

    {command("sysctl", ["-n", "machdep.cpu.brand_string"]),
     command("sysctl", ["-n", "hw.memsize"]), os}
  end

  defp postgres_line(conn) do
    settings =
      for name <- ["server_version", "synchronous_commit", "fsync", "wal_sync_method"] do
        %{rows: [[value]]} = Postgrex.query!(conn, "SHOW #{name}", [])
        {name, value}
      end

    {"server_version", version} = hd(settings)

    details =
      settings
      |> tl()
      |> Enum.map_join(", ", fn {name, value} -> "#{name} #{value}" end)

    "PostgreSQL #{version}, #{details}"
  end

  defp put_section(results, name, section) do
    pattern = ~r/<!-- case:#{name} -->.*?<!-- \/case:#{name} -->[ \t]*\n/s

    replaced =
      if Regex.match?(pattern, results) do
        Regex.replace(pattern, results, fn _match -> section end)
      else
        String.trim_trailing(results) <> "\n\n" <> section
      end

    # The placeholder an empty README holds goes once a case has figures.
    replaced
    |> String.replace("\nNone yet.\n", "\n")
    |> order_sections()
    |> String.trim()
    |> then(&("\n" <> &1 <> "\n"))
  end

  # In the order the README lists the cases, whatever order they ran in. A section of a case not
  # in the list goes last.
  #
  # Anything else between the markers, like a note written by hand or a section without its end,
  # is kept after the sections rather than dropped.
  defp order_sections(results) do
    pattern = ~r/<!-- case:([a-z0-9_-]+) -->.*?<!-- \/case:\1 -->/s
    sections = Regex.scan(pattern, results)

    rest =
      pattern
      |> Regex.replace(results, "")
      |> String.trim()

    ordered =
      sections
      |> Enum.sort_by(fn [_section, name] ->
        Enum.find_index(@case_order, &(&1 == name)) || length(@case_order)
      end)
      |> Enum.map(fn [section, _name] -> section end)

    joined = Enum.join(ordered, "\n\n")

    if rest == "", do: joined, else: joined <> "\n\n" <> rest
  end

  defp table({heading, columns, rows}) do
    header = "| " <> Enum.join(columns, " | ") <> " |"
    rule = "|" <> String.duplicate("---|", length(columns))

    body =
      Enum.map_join(rows, "\n", fn row -> "| " <> Enum.map_join(row, " | ", &cell/1) <> " |" end)

    """
    #### #{heading}

    #{header}
    #{rule}
    #{body}
    """
  end
end
