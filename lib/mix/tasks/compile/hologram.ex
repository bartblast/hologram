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

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SystemUtils
  alias Hologram.Compiler
  alias Hologram.Compiler.Cache
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Tracer
  alias Hologram.Reflection

  # How long an empty lock file is respected before it is presumed abandoned
  # (see the empty-content clause of validate_lock_file_and_proceed_accordingly/2).
  # The floor has two parts: the create-to-write gap the file may legitimately sit
  # empty for (microseconds normally, milliseconds under a preempting scheduler),
  # and the mtime granularity of the filesystem the age is measured against (a full
  # second on some filesystems). Anything above roughly 2 seconds is policy, and the
  # asymmetry picks the value: waiting a few extra seconds in the vanishingly rare
  # abandoned case costs nothing, while removing a live lock reintroduces the very
  # race this handling exists to close.
  # TODO: Consider lowering this towards the 2-second floor. The only cost of a lower
  # value is that abandoned empty locks are cleared sooner, and reaching that state
  # takes a kill signal landing inside the microsecond create-to-write window, so the
  # margin here mostly buys peace of mind. Once the fix has run in CI long enough to
  # show no lock file has ever been removed while its owner was still alive, the
  # margin can shrink.
  @abandoned_empty_lock_grace_period_s 5

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

      module_info_plt_dump_path =
        Path.join(build_dir, Reflection.module_info_plt_dump_file_name())

      call_graph_dump_path = Path.join(build_dir, Reflection.call_graph_dump_file_name())

      # The IR PLT and the call graph are kept between compiles (see Hologram.Compiler.Cache), and
      # the module infos they were last brought in line with, with the modules whose beams a save
      # can rewrite, are the before picture. The IR PLT holds the IR this compile reads, no more:
      # the modules of the diff first, for the graph patch, then the rest once the graph says what
      # is reachable.
      {cache, old_module_info_plt, module_info_dumped_at} =
        load_before_state(build_dir, call_graph_dump_path, sup)

      # Listed with the scan, so that the modules kept as editable and the module infos kept with
      # them describe the same moment.
      editable_beams = Reflection.list_editable_beams()
      editable_modules = MapSet.new(editable_beams, fn {module, _beam_path} -> module end)

      # Taken on a cold compile too, so that the modules its full scan covers are forgotten.
      compiled_modules =
        editable_beams
        |> Map.new()
        |> Tracer.take()

      new_module_info_plt =
        build_module_info_plt(
          cache.editable_modules,
          old_module_info_plt,
          module_info_dumped_at,
          editable_beams,
          compiled_modules,
          sup
        )

      module_digests_diff =
        Compiler.diff_module_info_plts(old_module_info_plt, new_module_info_plt)

      ir_plt = Compiler.patch_ir_plt!(cache.ir_plt, module_digests_diff)

      # The graph answers module questions from the module info PLT of the compile at hand.
      call_graph = %{cache.call_graph | module_info_plt: new_module_info_plt}

      # Before the patch, while the removed and edited modules still have their vertices and their
      # callers: every way a page's bundle depends on a module is a path to that module, so the
      # pages whose bundles can change are the ones these modules reach back to. Added modules need
      # no walk of their own, since a new module is only reachable through an edited one.
      reaching_modules =
        CallGraph.list_modules_reaching(
          call_graph,
          module_digests_diff.removed_modules ++ module_digests_diff.edited_modules
        )

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

      page_modules = Compiler.list_pages(new_module_info_plt)
      component_modules = Compiler.list_components(new_module_info_plt)

      Compiler.validate_page_modules(page_modules, new_module_info_plt)

      templatable_modules = page_modules ++ component_modules
      Compiler.build_missing_ir!(ir_plt, templatable_modules)

      # Runs here rather than in each module's own compilation: every module is compiled by now, so
      # a used component's __props__/0 is simply callable, with no compile-time dependency on it and
      # no deadlock when a component renders itself.
      Compiler.validate_prop_usages(templatable_modules, ir_plt)

      runtime_mfas = CallGraph.list_runtime_mfas(call_graph_for_runtime, page_modules)

      # Derived before the graph is split into runtime and page parts, so that the
      # applications reached from pages are named as well.
      app_versions =
        build_app_versions(cache.app_versions, call_graph_for_runtime, module_digests_diff)

      call_graph_for_pages = CallGraph.remove_runtime_mfas!(call_graph_for_runtime, runtime_mfas)

      # Every page loads the runtime script, so the JS bindings it registers are available
      # app-wide. A page bundle registering them again would only bundle a second copy of the
      # imported JavaScript module, which the two would then take turns overwriting.
      runtime_js_binding_modules =
        runtime_mfas
        |> Compiler.list_js_import_modules(ir_plt, new_module_info_plt)
        |> MapSet.new()

      {mfas_by_page, kept_pages} =
        Compiler.partition_pages_to_rebuild(page_modules, call_graph_for_pages, component_modules,
          pages_plt: cache.pages_plt,
          reaching_modules: reaching_modules,
          static_dir: opts[:static_dir],
          rebuild_all?: runtime_js_bindings_changed?(cache.runtime, runtime_js_binding_modules),
          relist_all?: runtime_mfas_changed?(cache.runtime, runtime_mfas)
        )

      kept_mfas_by_page =
        Enum.map(kept_pages, fn {page_module, page_state} -> {page_module, page_state.mfas} end)

      # Every entry file reads its IR from here on, so the IR it reads is built in one pass first,
      # and whatever an earlier compile kept that no entry file reads any more is dropped. A kept
      # page renders no entry file this time, but its IR stays, so that a later compile that does
      # rebuild it finds the IR it reads.
      ir_modules =
        Compiler.list_ir_modules(
          runtime_mfas,
          mfas_by_page ++ kept_mfas_by_page,
          new_module_info_plt
        )

      Compiler.build_missing_ir!(ir_plt, ir_modules)
      Compiler.prune_ir_plt(ir_plt, templatable_modules ++ ir_modules)

      # Filled by the entry file renderers as they go: each reachable function's JavaScript
      # is produced once per compile in the common case and read back by every entry file that
      # needs it.
      encode_plt = PLT.start(supervisor: sup)

      # The stack trace metadata of every module, which the bundles look up instead of asking the
      # VM about each module once per bundle. Built only when client stack traces are on, since the
      # bundles register no metadata otherwise.
      module_metadata =
        if Hologram.client_stacktraces?() do
          Compiler.build_module_metadata(new_module_info_plt)
        end

      entry_file_opts =
        Keyword.merge(opts,
          module_info_plt: new_module_info_plt,
          module_metadata: module_metadata
        )

      # The runtime bundle is kept like a page's: rebuilt when its inputs differ from the ones it
      # was built from, when a module it carries was edited, or when its file is gone.
      runtime_entry_files_info =
        if keep_runtime_bundle?(cache.runtime, reaching_modules,
             app_versions: app_versions,
             js_binding_modules: runtime_js_binding_modules,
             mfas: runtime_mfas,
             static_dir: opts[:static_dir]
           ) do
          []
        else
          runtime_entry_file_path =
            Compiler.create_runtime_entry_file(
              runtime_mfas,
              ir_plt,
              encode_plt,
              async_mfas,
              app_versions,
              entry_file_opts
            )

          [{"runtime", runtime_entry_file_path, "runtime"}]
        end

      page_entry_files_info =
        mfas_by_page
        |> Compiler.create_page_entry_files(
          ir_plt,
          encode_plt,
          async_mfas,
          runtime_js_binding_modules,
          entry_file_opts
        )
        |> Enum.map(fn {entry_name, entry_file_path} ->
          {entry_name, entry_file_path, "page"}
        end)

      entry_files_info = runtime_entry_files_info ++ page_entry_files_info

      old_build_static_artifacts =
        opts[:static_dir]
        |> File.ls!()
        |> Enum.map(fn file_name -> Path.join(opts[:static_dir], file_name) end)

      built_bundles_info = Compiler.bundle(entry_files_info, opts)

      # A kept bundle is the file an earlier compile wrote, with the digest it recorded, so it
      # belongs in the page digest PLT and among the artifacts the cleanup below keeps.
      kept_page_bundles_info =
        Enum.map(kept_pages, fn {_page_module, %{bundle_info: info}} -> info end)

      kept_bundles_info =
        if runtime_entry_files_info == [] do
          [cache.runtime.bundle_info | kept_page_bundles_info]
        else
          kept_page_bundles_info
        end

      bundles_info = built_bundles_info ++ kept_bundles_info

      new_build_static_artifacts =
        Enum.reduce(bundles_info, [], fn bundle_info, acc ->
          [bundle_info.static_bundle_path, bundle_info.static_source_map_path | acc]
        end)

      {page_digest_plt, page_digest_plt_dump_path} =
        Compiler.build_page_digest_plt(bundles_info, Keyword.put(opts, :supervisor, sup))

      PLT.dump(page_digest_plt, page_digest_plt_dump_path)
      CallGraph.dump(call_graph, call_graph_dump_path)
      PLT.dump(new_module_info_plt, module_info_plt_dump_path)

      # The dump time is kept with the infos, since the reuse guard compares them against it (see
      # Hologram.Compiler.Cache). Last, so that a compile that fails anywhere before leaves the
      # before picture of the last finished one, against which the partly patched IR PLT and call
      # graph are patched again.
      module_info_dumped_at = Compiler.module_info_dumped_at(module_info_plt_dump_path)
      module_infos = PLT.get_all(new_module_info_plt)
      Cache.put_module_infos(module_infos, module_info_dumped_at, editable_modules)
      Cache.put_app_versions(app_versions)

      # After the dumps as well: what is kept describes files that are on disk and a page digest PLT
      # that names them.
      keep_built_bundles(
        built_bundles_info,
        mfas_by_page,
        runtime_mfas,
        runtime_js_binding_modules,
        app_versions: app_versions,
        pages_plt: cache.pages_plt,
        page_modules: page_modules
      )

      Enum.each(old_build_static_artifacts -- new_build_static_artifacts, &File.rm!/1)

      Logger.info("Hologram: compiler finished")

      :ok
    after
      duration = System.monotonic_time() - start_time
      :telemetry.execute([:hologram, :compiler, :stop], %{duration: duration}, %{})
      DynamicSupervisor.stop(sup)
    end
  end

  # The versions of the applications the graph reaches, kept between compiles: an ordinary save edits
  # the project's own modules, which can move neither the set of applications the graph reaches nor
  # any of their versions (see Hologram.Compiler.app_versions_changed?/2).
  defp build_app_versions(nil, call_graph, _module_digests_diff) do
    Compiler.build_app_versions(call_graph)
  end

  defp build_app_versions(kept_app_versions, call_graph, module_digests_diff) do
    if Compiler.app_versions_changed?(module_digests_diff, Reflection.otp_app()) do
      Compiler.build_app_versions(call_graph)
    else
      kept_app_versions
    end
  end

  # A cold compile reads every module against the dump; a warm one reads the modules the compiler
  # reported among the beams a save can rewrite, and copies the rest of the kept entries (see
  # Hologram.Compiler.update_module_info_plt!/5). The cache holds the editable modules only between
  # two finished compiles, so nil means cold.
  defp build_module_info_plt(nil, old_plt, dumped_at, _editable_beams, _compiled_modules, sup) do
    Compiler.build_module_info_plt!(old_plt, dumped_at, supervisor: sup)
  end

  defp build_module_info_plt(
         editable_modules,
         old_plt,
         dumped_at,
         editable_beams,
         compiled_modules,
         sup
       ) do
    Compiler.update_module_info_plt!(old_plt, dumped_at, editable_modules, editable_beams,
      compiled_modules: compiled_modules,
      supervisor: sup
    )
  end

  defp compile_with_lock(opts) do
    lock_path = Path.join(opts[:build_dir], Reflection.compiler_lock_file_name())

    with_lock(lock_path, fn ->
      compile(opts)
    end)
  end

  # Records what this compile built, so that the next one can reuse the bundles of the pages an edit
  # does not reach: a state per page bundle it wrote, the runtime's inputs with its bundle, and no
  # state for a page that no longer exists (whose bundle the artifact cleanup has just deleted).
  defp keep_built_bundles(
         built_bundles_info,
         mfas_by_page,
         runtime_mfas,
         runtime_js_binding_modules,
         opts
       ) do
    mfas_by_page_map = Map.new(mfas_by_page)

    Enum.each(built_bundles_info, fn
      %{bundle_name: "page", entry_name: page_module} = bundle_info ->
        mfas = mfas_by_page_map[page_module]

        Cache.put_page(page_module, %{
          bundle_info: bundle_info,
          mfas: mfas,
          modules: page_state_modules(mfas)
        })

      %{bundle_name: "runtime"} = bundle_info ->
        Cache.put_runtime(%{
          app_versions: opts[:app_versions],
          bundle_info: bundle_info,
          js_binding_modules: runtime_js_binding_modules,
          mfas: runtime_mfas
        })
    end)

    opts[:pages_plt]
    |> PLT.keys()
    |> Kernel.--(opts[:page_modules])
    |> Enum.each(&Cache.delete_page/1)
  end

  # The runtime bundle carries the functions every page leaves out, so it is rebuilt when its MFAs,
  # the JS imports it registers or the app versions it names differ from the kept ones, and when a
  # module of those MFAs was edited: its functions are in the bundle, so their code is too. Both of
  # its files are required, since nothing else in the compile would recreate a missing source map.
  defp keep_runtime_bundle?(nil, _reaching_modules, _inputs), do: false

  defp keep_runtime_bundle?(kept_runtime, reaching_modules, inputs) do
    not Compiler.runtime_changed?(
      kept_runtime,
      inputs[:mfas],
      inputs[:js_binding_modules],
      inputs[:app_versions]
    ) and
      runtime_modules_untouched?(inputs[:mfas], reaching_modules) and
      Path.dirname(kept_runtime.bundle_info.static_bundle_path) == inputs[:static_dir] and
      File.exists?(kept_runtime.bundle_info.static_bundle_path) and
      File.exists?(kept_runtime.bundle_info.static_source_map_path)
  end

  defp runtime_modules_untouched?(runtime_mfas, reaching_modules) do
    runtime_mfas
    |> page_state_modules()
    |> MapSet.disjoint?(reaching_modules)
  end

  defp page_state_modules(mfas) do
    mfas
    |> Enum.map(fn {module, _function, _arity} -> module end)
    |> MapSet.new()
  end

  defp runtime_js_bindings_changed?(nil, _js_binding_modules), do: false

  defp runtime_js_bindings_changed?(kept_runtime, js_binding_modules) do
    kept_runtime.js_binding_modules != js_binding_modules
  end

  defp runtime_mfas_changed?(nil, _runtime_mfas), do: false

  defp runtime_mfas_changed?(kept_runtime, runtime_mfas) do
    kept_runtime.mfas != runtime_mfas
  end

  defp compiler_enabled? do
    # credo:disable-for-next-line Credo.Check.Warning.MixEnv
    Mix.env() not in [:dev, :test] or System.get_env("HOLOGRAM_START") == "1"
  end

  defp language_server_build?(opts) do
    path_components = Path.split(opts[:build_dir])
    Enum.any?(@ls_build_dirs, fn dir -> dir in path_components end)
  end

  # Returns the cache, the module info PLT to diff against, and the dump time the module info reuse
  # guard takes. The kept module infos are the proof that the kept IR PLT and call graph are exactly
  # in line with them, whatever another VM wrote to the build dir since, and they exist only between
  # two finished compiles. Without them (the first compile in a VM, or after a failed one) the cache
  # is emptied and the build dir is the before picture: the graph comes from its dump and the module
  # info dump written next to it says what changed.
  defp load_before_state(build_dir, call_graph_dump_path, sup) do
    case Cache.get() do
      %{module_infos: nil} ->
        :ok = Cache.reset()
        cache = Cache.get()

        # The two dumps are written together at the end of a compile, so a module info dump
        # without a graph dump is not a before picture: diffing against it would report no changes
        # and leave the empty graph with nothing to patch. Without the graph dump every module
        # counts as added, so the IR PLT and the graph are built in full.
        {module_info_plt, dumped_at} =
          if File.exists?(call_graph_dump_path) do
            CallGraph.load(cache.call_graph, call_graph_dump_path)

            {plt, _dump_path, dumped_at} =
              Compiler.maybe_load_module_info_plt(build_dir, supervisor: sup)

            {plt, dumped_at}
          else
            {PLT.start(supervisor: sup), nil}
          end

        {cache, module_info_plt, dumped_at}

      cache ->
        items = Map.to_list(cache.module_infos)
        module_info_plt = PLT.start(items: items, supervisor: sup)

        # Cleared before anything is patched in place: a compile that dies mid-patch can leave the
        # kept graph without edges that only its callers would rebuild, so the next compile must
        # start from the dumps rather than from a half-patched graph. The infos are put back last,
        # after the dumps.
        :ok = Cache.clear_module_infos()

        {cache, module_info_plt, cache.dumped_at}
    end
  end

  # The removal here shares the path-based race documented at
  # remove_lock_for_dead_process/2, in its narrowest form: only an integer comparison
  # separates the age check from the removal, where that function spends milliseconds
  # in a liveness check, and reaching this branch at all needs a lock abandoned inside
  # the microsecond window between creating it and writing the OS-level PID into it.
  # Still a reduction of what it replaces, which deleted every empty lock on sight,
  # with no age gate, on ordinary concurrent compiles.
  defp maybe_remove_abandoned_empty_lock(lock_path) do
    case File.stat(lock_path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} ->
        if System.os_time(:second) - mtime > @abandoned_empty_lock_grace_period_s do
          Logger.info("Hologram: removing abandoned empty lock file")
          File.rm(lock_path)
        end

      # The file is already gone: its owner either completed the acquisition and
      # then finished, or cleaned up after itself.
      {:error, _reason} ->
        :ok
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

  # Known, unclosed race, shared with maybe_remove_abandoned_empty_lock/1 and widest
  # here: the removal is by path, not owner-verified. Deciding that os_pid is dead
  # takes milliseconds (SystemUtils.os_process_alive?/1 shells out to ps or tasklist),
  # and by the time File.rm/1 runs, the file at this path may no longer be the one
  # that was diagnosed. Two invocations reading the same lock left
  # behind by a killed process both diagnose it dead; the first removes it, acquires
  # its own lock and starts compiling; the second's removal then deletes that live
  # lock, and both compile at once.
  #
  # Left as is deliberately. Rechecking the file's identity right before the removal
  # would only shrink the window from milliseconds to microseconds while making the
  # code look safe, and microsecond windows between two file operations are exactly
  # what made this lock flaky before (see the empty-content clause of
  # validate_lock_file_and_proceed_accordingly/2). Closing it properly means making
  # existence and ownership one atomic object, i.e. a lock directory - File.mkdir/1
  # is atomic and fails when the directory exists, with the OS-level PID in a file
  # inside it - which restructures acquisition, release and stale detection alike.
  # Worth doing only if this is ever actually observed: unlike the empty-lock race it
  # needs a lock orphaned by a killed process, which the cleanup in with_lock/2
  # prevents on every normal exit, plus two invocations landing in the liveness check
  # within the same few milliseconds.
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

  # An empty lock file is a lock in the middle of being acquired, not an invalid one:
  # with_lock/2 creates the file with File.open/2 and only then writes the owner's PID
  # into it, so a concurrent invocation can read it in between and must leave it alone.
  # Treating it as invalid would delete a lock that was just legitimately acquired and
  # let both compilations run at once.
  #
  # The empty state cannot be removed outright. The textbook fix is to write the PID to
  # a temp file and hard-link it into place - :file.make_link/2 is atomic and fails with
  # :eexist when the target exists - but hard links are not dependable on Windows, which
  # Hologram supports, and a platform fallback would reintroduce the very two-step
  # acquisition the idiom exists to remove.
  #
  # The one state left is an empty lock whose owner died between the two steps: nothing
  # would ever fill or remove it. Hence the grace period - an empty lock is respected
  # only while it is young, and the retry loop's stale check clears an abandoned one
  # shortly after the grace period expires.
  defp validate_lock_file_and_proceed_accordingly(lock_path, "") do
    maybe_remove_abandoned_empty_lock(lock_path)
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
