# credo:disable-for-this-file Credo.Check.Refactor.ABCSize
defmodule Mix.Tasks.Compile.Hologram do
  @moduledoc """
  Builds Hologram project JavaScript bundles, the call graph of the code,
  PLTs needed by the runtime and PLTs needed to speed up future compilation.
  """

  use Mix.Task.Compiler

  require Logger

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SystemUtils
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Reflection

  @impl Mix.Task.Compiler
  # If the options are strings, it means that the task was executed directly by the Elixir compiler.
  def run([hd | _tail]) when is_binary(hd) do
    opts = build_default_opts()

    if elixir_ls_build?(opts) do
      :ok
    else
      run(opts)
    end
  end

  @impl Mix.Task.Compiler
  def run([]) do
    run(build_default_opts())
  end

  @doc """
  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/mix/tasks/compile.hologram/README.md
  """
  @impl Mix.Task.Compiler
  def run(opts) do
    lock_path = Path.join(opts[:build_dir], Reflection.compiler_lock_file_name())

    with_lock(lock_path, fn ->
      compile(opts)
    end)
  end

  defp bin_available?(path) do
    cmd_args = ["--version"]

    cmd_opts = [parallelism: true, stderr_to_stdout: true]

    try do
      case SystemUtils.cmd_cross_platform(path, cmd_args, cmd_opts) do
        {_exit_msg, 0} -> true
        _cmd_result -> false
      end
    rescue
      _e -> false
    end
  end

  defp build_default_opts do
    root_dir = Reflection.root_dir()
    assets_dir = Path.join([root_dir, "deps", "hologram", "assets"])
    build_dir = Reflection.build_dir()
    node_modules_path = Path.join(assets_dir, "node_modules")

    [
      assets_dir: assets_dir,
      build_dir: build_dir,
      esbuild_bin_path: Path.join([node_modules_path, ".bin", "esbuild"]),
      # Biome is almost x20 faster than Prettier in Hologram benchmarks
      formatter_bin_path: Path.join([node_modules_path, ".bin", "biome"]),
      js_dir: Path.join(assets_dir, "js"),
      static_dir: Path.join([root_dir, "priv", "static", "hologram"]),
      tmp_dir: Path.join(build_dir, "tmp")
    ]
  end

  defp compile(opts) do
    Logger.info("Hologram: compiler started")

    assets_dir = opts[:assets_dir]
    build_dir = opts[:build_dir]

    File.mkdir_p!(build_dir)
    File.mkdir_p!(opts[:static_dir])
    File.mkdir_p!(opts[:tmp_dir])

    Compiler.maybe_install_js_deps(assets_dir, build_dir)

    opts = maybe_adjust_formatter_bin_path(opts)

    {old_module_digest_plt, module_digest_plt_dump_path} =
      Compiler.maybe_load_module_digest_plt(build_dir)

    new_module_digest_plt = Compiler.build_module_digest_plt!()

    module_digests_diff =
      Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)

    # Building IR PLT from scratch is faster that dumping it to a file,
    # and then loading and patching it (benchmarked on an app with 1628 modules):
    # build: ~310 ms
    # dump: ~350 ms
    # load: ~465 ms
    # patch: not benchmarked
    ir_plt = Compiler.build_ir_plt()

    {call_graph, call_graph_dump_path} = Compiler.maybe_load_call_graph(build_dir)
    CallGraph.patch(call_graph, ir_plt, module_digests_diff)

    call_graph_for_runtime =
      call_graph
      |> CallGraph.clone()
      # DEFER: In case the list of manually ported MFAs grows to ~32 vertices,
      # consider using similar strategy to CallGraph.remove_runtime_mfas!/2
      # or implement opts param for Digraph.remove_vertices/2 to allow rebuilding the graph.
      |> CallGraph.remove_manually_ported_mfas()

    runtime_mfas = CallGraph.list_runtime_mfas(call_graph_for_runtime)

    runtime_entry_file_path = Compiler.create_runtime_entry_file(runtime_mfas, ir_plt, opts)

    page_modules = Reflection.list_pages()

    Compiler.validate_page_modules(page_modules)

    call_graph_for_pages = CallGraph.remove_runtime_mfas!(call_graph_for_runtime, runtime_mfas)

    page_entry_files_info =
      page_modules
      |> Compiler.create_page_entry_files(call_graph_for_pages, ir_plt, opts)
      |> Enum.map(fn {entry_name, entry_file_path} ->
        {entry_name, entry_file_path, "page"}
      end)

    page_entry_file_paths =
      Enum.map(page_entry_files_info, fn {_entry_name, entry_file_path, _bundle_name} ->
        entry_file_path
      end)

    Compiler.format_files([runtime_entry_file_path | page_entry_file_paths], opts)

    entry_files_info = [{"runtime", runtime_entry_file_path, "runtime"} | page_entry_files_info]

    old_build_static_artifacts =
      opts[:static_dir]
      |> File.ls!()
      |> Enum.map(fn file_name -> Path.join(opts[:static_dir], file_name) end)

    bundles_info = Compiler.bundle(entry_files_info, opts)

    new_build_static_artifacts =
      Enum.reduce(bundles_info, [], fn bundle_info, acc ->
        [bundle_info.static_bundle_path, bundle_info.static_source_map_path | acc]
      end)

    {page_digest_plt, page_digest_plt_dump_path} =
      Compiler.build_page_digest_plt(bundles_info, opts)

    PLT.dump(page_digest_plt, page_digest_plt_dump_path)
    CallGraph.dump(call_graph, call_graph_dump_path)
    PLT.dump(new_module_digest_plt, module_digest_plt_dump_path)

    Enum.each(old_build_static_artifacts -- new_build_static_artifacts, &File.rm!/1)

    Logger.info("Hologram: compiler finished")

    :ok
  end

  defp elixir_ls_build?(opts) do
    String.contains?(opts[:build_dir], "/.elixir_ls/")
  end

  defp maybe_adjust_formatter_bin_path(opts) do
    system_formatter_path = "biome"

    formatter_bin_path =
      Enum.find([opts[:formatter_bin_path], system_formatter_path], &bin_available?/1)

    case formatter_bin_path do
      nil ->
        raise RuntimeError,
          message: """
          Biome Formatter failed to run

          Neither the bundled biome binary nor a system-installed biome could be executed.
          This can happen on systems where dynamically linked binaries are not supported,
          such as NixOS or musl-based distributions (e.g., Alpine Linux).

          To fix this, install biome and ensure it's available in your PATH.
          For installation options, see: https://biomejs.dev/guides/manual-installation/
          """

      path ->
        Keyword.put(opts, :formatter_bin_path, path)
    end
  end

  defp maybe_remove_file(lock_path) do
    if File.exists?(lock_path) do
      File.rm(lock_path)
    end
  end

  defp maybe_remove_stale_lock(lock_path) do
    if File.exists?(lock_path) do
      case File.read(lock_path) do
        {:ok, os_pid_str} ->
          validate_lock_file_and_proceed_accordingly(lock_path, os_pid_str)

        {:error, _reason} ->
          remove_unreadable_lock_file(lock_path)
      end
    end
  end

  defp remove_lock_file_with_invalid_os_pid(lock_path) do
    Logger.info("Hologram: removing lock file with invalid OS-level PID format")
    File.rm(lock_path)
  end

  defp remove_lock_for_dead_process(lock_path, os_pid) do
    Logger.info(
      "Hologram: removing stale lock file (OS-level process #{os_pid} no longer exists)"
    )

    File.rm(lock_path)
  end

  defp remove_unreadable_lock_file(lock_path) do
    Logger.info("Hologram: removing unreadable lock file")
    File.rm(lock_path)
  end

  defp validate_lock_file_and_proceed_accordingly(lock_path, os_pid_str) do
    case Integer.parse(os_pid_str) do
      {os_pid, _remainder} ->
        if not SystemUtils.os_process_alive?(os_pid) do
          remove_lock_for_dead_process(lock_path, os_pid)
        end

      :error ->
        remove_lock_file_with_invalid_os_pid(lock_path)
    end
  end

  defp with_lock(lock_path, fun) do
    lock_path
    |> Path.dirname()
    |> File.mkdir_p!()

    maybe_remove_stale_lock(lock_path)

    case File.open(lock_path, [:write, :exclusive]) do
      {:ok, file} ->
        # Write OS-level PID to lock file for stale lock detection
        IO.write(file, "#{System.pid()}")
        File.close(file)

        try do
          fun.()
        catch
          kind, reason ->
            maybe_remove_file(lock_path)
            :erlang.raise(kind, reason, __STACKTRACE__)
        after
          maybe_remove_file(lock_path)
        end

      {:error, :eexist} ->
        Logger.info("Hologram: compiler already running, waiting...")
        :timer.sleep(1_000)
        with_lock(lock_path, fun)

      {:error, reason} ->
        raise "Hologram: failed to acquire compiler lock: #{inspect(reason)}"
    end
  end
end
