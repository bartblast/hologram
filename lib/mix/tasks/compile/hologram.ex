defmodule Mix.Tasks.Compile.Hologram do
  @moduledoc """
  Builds Hologram project JavaScript bundles, the call graph of the code,
  PLTs needed by the runtime and PLTs needed to speed up future compilation.

  ## Telemetry

  Emits the following events around each compilation run, i.e. the critical
  section guarded by the compiler lock:

    * `[:hologram, :compiler, :start]` - dispatched when a compilation begins,
      with measurement `%{system_time: System.system_time()}`.

    * `[:hologram, :compiler, :stop]` - dispatched when a compilation ends,
      whether it succeeds or raises, with measurement `%{duration: native_time}`
      in `System.monotonic_time/0` native units.
  """

  use Mix.Task.Compiler

  require Logger

  alias Hologram.Auth.RoleGrant
  alias Hologram.Commons.PLT
  alias Hologram.Commons.SystemUtils
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.DB.Mapper
  alias Hologram.Entity.Model
  alias Hologram.Entity.Validator, as: EntityValidator
  alias Hologram.Policy
  alias Hologram.Policy.Validator, as: PolicyValidator
  alias Hologram.Reflection

  @ls_build_dirs [".elixir_ls", ".elixir-tools", ".expert", ".lexical"]

  @impl Mix.Task.Compiler
  # If the options are strings, it means that the task was executed directly by the Elixir compiler.
  def run([hd | _tail]) when is_binary(hd) do
    run(build_default_opts())
  end

  @doc """
  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/mix/tasks/compile.hologram/README.md
  """
  @impl Mix.Task.Compiler
  def run(opts) do
    opts = Keyword.merge(build_default_opts(), opts)

    # Positioned before the skip guards - the cheap whole-model checks must run on every
    # invocation (including dev/test and language-server builds), while only the expensive
    # bundle build stays behind them.
    validate_data_model!()

    result =
      cond do
        opts[:force?] -> compile_with_lock(opts)
        language_server_build?(opts) -> :noop
        !compiler_enabled?() -> :noop
        true -> compile_with_lock(opts)
      end

    # TODO: Remove this block together with refresh_umbrella_app_manifests/0
    # (see the removal note there), and inline the cond above back into the
    # function body - the result binding exists only to run this afterwards.
    if not language_server_build?(opts) do
      refresh_umbrella_app_manifests()
    end

    result
  end

  defp build_default_opts do
    assets_dir = Path.join(Reflection.hologram_dep_dir(), "assets")
    build_dir = Reflection.build_dir()
    node_modules_path = Path.join(assets_dir, "node_modules")

    [
      assets_dir: assets_dir,
      build_dir: build_dir,
      esbuild_bin_path: Path.join([node_modules_path, ".bin", "esbuild"]),
      js_dir: Path.join(assets_dir, "js"),
      node_modules_path: node_modules_path,
      static_dir: Path.join(Reflection.otp_app_static_dir(), "hologram"),
      tmp_dir: Path.join(build_dir, "tmp")
    ]
  end

  defp compile(opts) do
    {:ok, sup} = DynamicSupervisor.start_link(strategy: :one_for_one)

    start_time = System.monotonic_time()
    :telemetry.execute([:hologram, :compiler, :start], %{system_time: System.system_time()}, %{})

    try do
      Logger.info("Hologram: compiler started")

      assets_dir = opts[:assets_dir]
      build_dir = opts[:build_dir]

      File.mkdir_p!(build_dir)
      File.mkdir_p!(opts[:static_dir])
      File.mkdir_p!(opts[:tmp_dir])

      Compiler.maybe_install_js_deps(assets_dir, build_dir)

      {old_module_digest_plt, module_digest_plt_dump_path} =
        Compiler.maybe_load_module_digest_plt(build_dir, supervisor: sup)

      new_module_digest_plt = Compiler.build_module_digest_plt!(supervisor: sup)

      module_digests_diff =
        Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)

      # Building IR PLT from scratch is faster that dumping it to a file,
      # and then loading and patching it (benchmarked on an app with 1628 modules):
      # build: ~310 ms
      # dump: ~350 ms
      # load: ~465 ms
      # patch: not benchmarked
      ir_plt = Compiler.build_ir_plt(supervisor: sup)

      {call_graph, call_graph_dump_path} =
        Compiler.maybe_load_call_graph(build_dir, supervisor: sup)

      call_graph
      |> CallGraph.patch(ir_plt, module_digests_diff)
      |> CallGraph.add_non_discoverable_edges()

      # Must be computed before remove_manually_ported_mfas/1 strips the Task.await/1 vertex.
      async_mfas = CallGraph.list_async_mfas(call_graph)

      call_graph_for_runtime =
        call_graph
        |> CallGraph.clone(supervisor: sup)
        # DEFER: In case the list of manually ported MFAs grows to ~32 vertices,
        # consider using similar strategy to CallGraph.remove_runtime_mfas!/2
        # or implement opts param for Digraph.remove_vertices/2 to allow rebuilding the graph.
        |> CallGraph.remove_manually_ported_mfas()

      page_modules = Reflection.list_pages()

      Compiler.validate_page_modules(page_modules)

      # Derived before the graph is split, so that a component reached through a runtime MFA is
      # still counted as one the page can reach.
      {page_windows_plt, page_windows_plt_dump_path} =
        page_modules
        |> Compiler.build_page_windows(call_graph_for_runtime)
        |> Compiler.build_page_windows_plt(Keyword.put(opts, :supervisor, sup))

      runtime_mfas = CallGraph.list_runtime_mfas(call_graph_for_runtime, page_modules)

      # Derived before the graph is split into runtime and page parts, so that the
      # applications reached from pages are named as well.
      app_versions = Compiler.build_app_versions(call_graph_for_runtime)

      runtime_entry_file_path =
        Compiler.create_runtime_entry_file(
          runtime_mfas,
          ir_plt,
          async_mfas,
          app_versions,
          opts
        )

      call_graph_for_pages = CallGraph.remove_runtime_mfas!(call_graph_for_runtime, runtime_mfas)

      page_entry_files_info =
        page_modules
        |> Compiler.create_page_entry_files(call_graph_for_pages, ir_plt, async_mfas, opts)
        |> Enum.map(fn {entry_name, entry_file_path} ->
          {entry_name, entry_file_path, "page"}
        end)

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
        Compiler.build_page_digest_plt(bundles_info, Keyword.put(opts, :supervisor, sup))

      PLT.dump(page_digest_plt, page_digest_plt_dump_path)
      PLT.dump(page_windows_plt, page_windows_plt_dump_path)
      CallGraph.dump(call_graph, call_graph_dump_path)
      PLT.dump(new_module_digest_plt, module_digest_plt_dump_path)

      Enum.each(old_build_static_artifacts -- new_build_static_artifacts, &File.rm!/1)

      Logger.info("Hologram: compiler finished")

      :ok
    after
      duration = System.monotonic_time() - start_time
      :telemetry.execute([:hologram, :compiler, :stop], %{duration: duration}, %{})
      DynamicSupervisor.stop(sup)
    end
  end

  defp compile_with_lock(opts) do
    lock_path = Path.join(opts[:build_dir], Reflection.compiler_lock_file_name())

    with_lock(lock_path, fn ->
      compile(opts)
    end)
  end

  defp compiler_enabled? do
    # credo:disable-for-next-line Credo.Check.Warning.MixEnv
    Mix.env() not in [:dev, :test] or System.get_env("HOLOGRAM_START") == "1"
  end

  defp language_server_build?(opts) do
    path_components = Path.split(opts[:build_dir])
    Enum.any?(@ls_build_dirs, fn dir -> dir in path_components end)
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

  # Phoenix's code reloader (up to 1.8.9) treats the per-app compile.lock files in
  # the umbrella build dir as configuration inputs, and refuses to reload any
  # umbrella app whose compile.lock is newer than its Elixir compile manifest.
  # Every Mix invocation bumps the locks without necessarily recompiling anything,
  # so in an umbrella the check fails from boot onwards - every live reload and
  # every request served through the Phoenix.CodeReloader plug raises
  # "could not compile application". Touching the manifests right after the
  # Hologram compiler runs keeps them newer than the locks, which lets the check
  # pass without changing what gets recompiled. Single-app projects have no
  # in-umbrella deps, so this is a no-op for them.
  # Fixed upstream after Phoenix 1.8.9 (phoenixframework/phoenix#6753).
  # TODO: Remove once Hologram requires a Phoenix version containing the fix.
  defp refresh_umbrella_app_manifests do
    build_lib_dir = Path.join(Mix.Project.build_path(), "lib")

    umbrella_apps()
    |> Enum.map(&Path.join([build_lib_dir, to_string(&1), ".mix", "compile.elixir"]))
    |> Enum.filter(&File.exists?/1)
    |> Enum.each(&File.touch!/1)
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

  # Lists all apps of the enclosing umbrella project, whether the compiler runs in
  # the umbrella root context or in a child app context. Empty in single-app projects.
  # TODO: Remove together with refresh_umbrella_app_manifests/0 (see the removal
  # note there), which is its only caller.
  defp umbrella_apps do
    case Mix.Project.apps_paths() do
      nil ->
        case umbrella_sibling_apps() do
          [] -> []
          sibling_apps -> [Mix.Project.config()[:app] | sibling_apps]
        end

      apps_paths ->
        Map.keys(apps_paths)
    end
  end

  # TODO: Remove together with refresh_umbrella_app_manifests/0 (see the removal
  # note there) - umbrella_apps/0 is its only caller.
  defp umbrella_sibling_apps do
    Mix.Dep.cached()
    |> Enum.filter(& &1.opts[:in_umbrella])
    |> Enum.map(& &1.app)
  end

  defp validate_data_model! do
    RoleGrant.reset_resolution_cache()
    Model.reset_caches()
    Policy.reset_model_facts_cache()

    entity_types = Reflection.list_entities()

    EntityValidator.validate_model!(entity_types)
    PolicyValidator.validate_model!(entity_types)

    # The mapping value is discarded - only the fail-fast derivation checks matter here.
    Mapper.derive!(entity_types)

    :ok
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
