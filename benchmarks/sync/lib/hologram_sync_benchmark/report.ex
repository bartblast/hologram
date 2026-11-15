defmodule HologramSyncBenchmark.Report do
  @moduledoc false

  # Writes a case's figures into the README's results, replacing what an earlier run of the same
  # case wrote and leaving the other cases' sections as they were, so cases can be run one at a
  # time. Each section says where its figures come from: the commit, the machine, the database
  # and the options, since a figure means nothing without them.

  alias HologramSyncBenchmark.Measure

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
  run was given, and `figure` the case's clients-per-node figure. `tables` are `{heading,
  columns, rows}`, each row a list of cells.
  """
  @spec write_case!(String.t(), String.t(), String.t(), [String.t()], String.t(), [
          {String.t(), [String.t()], [[term]]}
        ]) :: :ok
  def write_case!(name, title, run_line, options, figure, tables) do
    :ok = check_readme!()

    section = """
    <!-- case:#{name} -->
    ### #{title}

    #{run_line}

    #{Enum.map_join(options, "\n", &("- " <> &1))}

    Clients per node: **#{figure}**

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

  Of the database's counters only the rows scanned: a fill is short against the settle around
  it, so the commits and time the idle rate takes off swamp the fill's own, and those come out as
  noise, negative ones included.
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
      fill.db.tup_returned,
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
      "DB rows scanned",
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

    [
      result.clients,
      steady.rate,
      steady.p50_ms,
      steady.p95_ms,
      steady.p99_ms,
      steady.max_ms,
      steady.missing,
      steady.cpu_ms_per_write,
      steady.cpu_ms_per_write / result.clients,
      steady.db.xact_commit,
      steady.db.tup_returned,
      steady.db.tup_fetched,
      steady.db.active_ms,
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
      "p50 ms",
      "p95 ms",
      "p99 ms",
      "Max ms",
      "Missing",
      "CPU ms per write",
      "CPU ms per write per client",
      "DB commits per write",
      "DB rows scanned per write",
      "DB rows fetched per write",
      "DB ms per write",
      "Step passed"
    ]
  end

  # Autovacuum running mid-step puts its work into the step's database figures.
  defp passed_cell(result) do
    passed = if result.passed, do: "yes", else: "no"

    if result.autovacuum_ran, do: passed <> ", autovacuum ran", else: passed
  end

  # Standard output only, so a warning on standard error can't pass for the answer.
  defp command(command, args) do
    case System.cmd(command, args, stderr_to_stdout: false) do
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

    "#{cpu || "unknown CPU"}, #{cores} cores, #{memory}, #{os || "unknown OS"}"
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
    |> String.trim()
    |> then(&("\n" <> &1 <> "\n"))
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
