defmodule Mix.Tasks.Compile.Hologram do
  @moduledoc """
  Builds Hologram project JavaScript bundles, the call graph of the code,
  PLTs needed by the runtime and PLTs needed to speed up future compilation.

  ## Batches

  The pages whose bundles a compile rebuilds are bundled in batches, which a caller that wants some
  pages before others (live reload, for the pages open in the browser) orders with two options:

    * `:next_batch` - called with the pages still to build (a `MapSet`) and the page links (a map
      from each page to the `MapSet` of pages it links to, as the last compile that built the page
      found them, or as this compile finds them for a page no compile has built), returns the
      pages to build now, a non-empty list of some of them, or `:stop` to leave the rest pending
      for the next compile. The runtime bundle, when it is rebuilt, is built with the first batch,
      or alone when the first answer is `:stop`. Defaults to every page in one batch.

    * `:bundles_built` - called after each batch is on disk and named by the page digest PLT dump,
      with the page modules built, preceded by `:runtime` when the runtime bundle was built.
      Defaults to doing nothing.

  ## Build dir

  A compile leaves four files in the build dir, so that the first compile in the next VM (the next
  `mix` command, say) reuses what this one built:

    * the call graph dump and the module info dump - the before picture: the graph of what the
      pages reach and the module infos it was brought in line with, which the next compile diffs
      the beams against.

    * the compile state dump - the after picture: what each page and the runtime bundle were built
      from, the pages still to build and what the compile derived for the bundles. The next
      compile keeps the bundles the diff does not reach.

    * the page digest dump - the digest of each page's bundle, which the router serves.

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
      bundles_built: fn _built -> :ok end,
      esbuild_bin_path: Path.join([node_modules_path, ".bin", "esbuild"]),
      js_dir: Path.join(assets_dir, "js"),
      next_batch: fn remaining_pages, _links -> MapSet.to_list(remaining_pages) end,
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

      compile_state_dump_path =
        Path.join(build_dir, Reflection.compile_state_dump_file_name())

      # The IR PLT and the call graph are kept between compiles (see Hologram.Compiler.Cache), and
      # the module infos they were last brought in line with, with the modules whose beams a save
      # can rewrite, are the before picture. The IR PLT holds the IR this compile reads, no more:
      # the modules the graph patch rebuilds first, then the ones the walk reaches, then the rest
      # once the graph says what is reachable. The dump time is the mtime of the module info dump
      # the before picture came from: the one this VM kept, or the one the first compile in a VM
      # loaded.
      {cache, old_module_info_plt, before_dumped_at} =
        load_before_state(build_dir, call_graph_dump_path, compile_state_dump_path, sup)

      # Listed with the scan, so that the modules kept as editable and the module infos kept with
      # them describe the same moment.
      editable_beams = Reflection.list_editable_beams()
      editable_modules = MapSet.new(editable_beams, fn {module, _beam_path} -> module end)

      # Taken on a cold compile too, so that the modules its full scan covers are forgotten.
      compiled_modules =
        editable_beams
        |> Map.new()
        |> Tracer.take()

      {new_module_info_plt, module_digests_diff, infos_changed?} =
        build_module_info_plt(
          cache,
          old_module_info_plt,
          before_dumped_at,
          editable_beams,
          compiled_modules,
          sup
        )

      # Everything a bundle depends on besides its modules. Kept bundles built with other inputs
      # (another Hologram build, another esbuild, client stack traces toggled) are forgotten before
      # anything reads them, so every page and the runtime are built again (see
      # Hologram.Compiler.Cache.forget_bundles/0).
      bundle_inputs = Compiler.build_bundle_inputs(new_module_info_plt, opts)
      cache = keep_bundle_inputs(cache, bundle_inputs)

      # The files esbuild read for the kept bundles, beyond Hologram's own (see
      # Hologram.Compiler.bundle/4): a bundle inlines them, and no beam moves when one is edited.
      # Fingerprinted once, and each kept bundle compared on its own record, so that a bundle that
      # read an older content of a file than another is rebuilt too.
      js_fingerprints =
        cache.js_input_paths
        |> MapSet.to_list()
        |> Compiler.fingerprint_js_inputs(nil)

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

      # The walk below starts from the pages and reads each page's layout.
      page_modules = Compiler.list_pages(new_module_info_plt)
      Compiler.validate_page_modules(page_modules, new_module_info_plt)

      # The IR of every removed and edited module is dropped, whether or not the graph holds the
      # module: the IR PLT keeps the templatables' IR between compiles, and an edited component no
      # page reaches is read again by the prop usage validation. The IR this compile reads is built
      # as it is asked for: the modules the patch rebuilds first, then the ones the walk reaches,
      # then the templatables and what the entry files read.
      ir_plt =
        Compiler.delete_module_ir(
          cache.ir_plt,
          module_digests_diff.removed_modules ++ module_digests_diff.edited_modules
        )

      # The graph holds the modules the pages, the runtime and the broadcast callers reach, no more
      # (see Hologram.Compiler.build_reach!/3), so only the modules of the diff it holds or must
      # come to hold are patched. On a build into an empty build dir those are the pages and the
      # broadcast callers, from which the walk grows the graph.
      graph_diff = CallGraph.narrow_diff(call_graph, module_digests_diff)

      Compiler.build_missing_ir!(ir_plt, graph_diff.edited_modules ++ graph_diff.added_modules)

      call_graph
      |> CallGraph.patch(ir_plt, graph_diff)
      |> CallGraph.add_non_discoverable_edges()

      # Nothing patched and nothing walked: the graph is the one the last finished compile ended with,
      # so what that compile derived from the graph alone still holds.
      graph_unchanged? =
        graph_diff == %{added_modules: [], edited_modules: [], removed_modules: []}

      # Grows the graph by the modules the patched functions start reaching, their IR included. A
      # compile whose patch touched nothing the graph holds reaches nothing new and does not walk.
      built_modules =
        if graph_unchanged?, do: [], else: Compiler.build_reach!(call_graph, ir_plt, graph_diff)

      # Must be computed before remove_manually_ported_mfas/1 strips the Task.await/1 vertex.
      async_mfas = list_async_mfas(cache.encoding_inputs, call_graph, graph_unchanged?)

      runtime_kept? = runtime_kept?(cache.runtime, graph_unchanged?, module_digests_diff)

      call_graph_for_runtime = build_runtime_graph(call_graph, runtime_kept?, sup)

      component_modules = Compiler.list_components(new_module_info_plt)
      templatable_modules = page_modules ++ component_modules

      template_modules =
        validate_prop_usages(
          templatable_modules,
          module_digests_diff,
          cache.template_modules,
          ir_plt
        )

      runtime_mfas =
        list_runtime_mfas(cache.runtime, call_graph_for_runtime, page_modules, runtime_kept?)

      # What the runtime's dynamic calls open for every page, taken while the runtime graph still
      # holds the runtime's MFAs (build_pages_graph/2 below takes them out), and kept when they are.
      runtime_dynamic_calls =
        list_runtime_dynamic_calls(
          cache.runtime,
          call_graph_for_runtime,
          runtime_mfas,
          ir_plt,
          runtime_kept?
        )

      # Which reflection functions each page can call (see Hologram.Compiler.DynamicCallGate): given
      # to every listing of pages, the kept pages' relisting included.
      gate = %{ir_plt: ir_plt, runtime: runtime_dynamic_calls}

      # Derived before the graph is split into runtime and page parts, so that the
      # applications reached from pages are named as well. Kept whenever the runtime's MFAs are:
      # the walk built nothing then, and no dependency was edited.
      app_versions =
        build_app_versions(
          cache.app_versions,
          call_graph_for_runtime,
          module_digests_diff,
          built_modules
        )

      call_graph_for_pages = build_pages_graph(call_graph_for_runtime, runtime_mfas)

      # Every page loads the runtime script, so the JS bindings it registers are available
      # app-wide. A page bundle registering them again would only bundle a second copy of the
      # imported JavaScript module, which the two would then take turns overwriting.
      runtime_js_binding_modules =
        runtime_mfas
        |> Compiler.list_js_import_modules(ir_plt, new_module_info_plt)
        |> MapSet.new()

      {pages_to_rebuild, kept_pages} =
        Compiler.partition_pages_to_rebuild(page_modules, call_graph_for_pages,
          gate: gate,
          js_fingerprints: js_fingerprints,
          page_mfas_plt: cache.page_mfas_plt,
          pages_plt: cache.pages_plt,
          pending_pages: cache.pending_pages,
          reaching_modules: reaching_modules,
          static_dir: opts[:static_dir],
          rebuild_all?: runtime_js_bindings_changed?(cache.runtime, runtime_js_binding_modules),
          relist_all?:
            runtime_mfas_changed?(cache.runtime, runtime_mfas) or
              runtime_dynamic_calls_changed?(cache.runtime, runtime_dynamic_calls)
        )

      # A compile that kept the runtime's MFAs has no pages graph yet: it relists no kept page, so it
      # needs one only for pages to rebuild, and one that rebuilds none makes none.
      call_graph_for_pages =
        ensure_pages_graph(call_graph_for_pages, call_graph, runtime_mfas, pages_to_rebuild, sup)

      # Pending until their bundles are built, so that the pages this compile does not get to are
      # rebuilt by the next one, whether or not its own edit reaches them.
      Cache.put_pending_pages(pages_to_rebuild)

      old_page_states = list_old_page_states(pages_to_rebuild, cache.pages_plt)

      recorded_pages =
        MapSet.new(old_page_states, fn {page_module, _page_state} -> page_module end)

      # A page to rebuild that no compile has built has no state to take its modules from, which is
      # every page on a build into an empty build dir or on the first compile in a VM, so it is
      # listed here, before the prune, and its own MFA list stands in for one; its batch reuses the
      # list. The pages with a state, every page a live-reload save rebuilds, are listed with their
      # batches.
      unrecorded_mfas_by_page =
        pages_to_rebuild
        |> Enum.reject(&MapSet.member?(recorded_pages, &1))
        |> Compiler.list_mfas_by_page(call_graph_for_pages, gate: gate)

      # The modules each page reaches: as its last built state recorded them, or as this compile
      # lists them for a page that has no state.
      modules_by_page =
        Enum.map(kept_pages ++ old_page_states, fn {page_module, page_state} ->
          {page_module, page_state.modules}
        end) ++
          Enum.map(unrecorded_mfas_by_page, fn {page_module, mfas} ->
            {page_module, page_state_modules(mfas)}
          end)

      # What an earlier compile kept that no page or the runtime reaches any more is dropped first,
      # encodings included: the encodings go with the modules this prune drops and with the removed
      # modules, whose IR was deleted before it. A component no page reaches keeps no IR: the prop
      # usage validation builds it when it checks the component (see validate_prop_usages/4). A page
      # rebuilt reads mostly what its old state names, and the IR it reads for the first time is
      # built with its batch. The IR of a page with no state is kept too: on a build into an empty
      # build dir the diff has just built the IR of every module, which pruning it would only have
      # the pages build again. A kept page renders no entry file this time, but its IR stays, so
      # that a later compile that does rebuild it finds the IR it reads.
      kept_modules =
        Compiler.list_kept_modules(runtime_mfas, modules_by_page, new_module_info_plt)

      dropped_modules = Compiler.prune_ir_plt(ir_plt, kept_modules)

      # Filled by the entry file renderers as they go, and kept between compiles (see
      # Hologram.Compiler.Cache): each reachable function's JavaScript is produced once and read back
      # by every entry file that needs it, in this compile and the next ones. What a function's
      # JavaScript depends on besides its module's IR is compared with what the kept encodings were
      # made with; while it holds, only the edited modules' functions are encoded again.
      encoding_inputs = %{
        async_mfas: async_mfas,
        client_stacktraces?: Hologram.client_stacktraces?()
      }

      encode_plt =
        cache.encode_plt
        |> patch_encode_plt(cache.encoding_inputs, encoding_inputs, module_digests_diff)
        |> Compiler.delete_module_encodings(
          dropped_modules ++ module_digests_diff.removed_modules
        )

      # The stack trace metadata of every module, which the bundles look up instead of asking the
      # VM about each module once per bundle. Built only when client stack traces are on, since the
      # bundles register no metadata otherwise. Kept between compiles and patched with the diff, since
      # an entry moves only with its module's beam.
      module_metadata =
        build_module_metadata(cache.module_metadata, module_digests_diff, new_module_info_plt)

      entry_file_opts =
        Keyword.merge(opts,
          module_info_plt: new_module_info_plt,
          module_metadata: module_metadata
        )

      # The runtime bundle is kept like a page's: rebuilt when its inputs differ from the ones it
      # was built from, when a module it carries was edited, or when its file is gone. The client
      # config it sets is one of its inputs (see Hologram.Compiler.client_config/0): the pages carry
      # none of it.
      client_config = Compiler.client_config()

      runtime_entry_files_info =
        if keep_runtime_bundle?(cache.runtime, reaching_modules,
             app_versions: app_versions,
             client_config: client_config,
             js_binding_modules: runtime_js_binding_modules,
             js_fingerprints: js_fingerprints,
             mfas: runtime_mfas,
             static_dir: opts[:static_dir]
           ) do
          []
        else
          # The runtime entry file is rendered before the batches, so the IR it reads is built here,
          # and only here: a kept runtime reads none. Each batch builds its pages' before rendering
          # theirs.
          runtime_mfas
          |> Compiler.list_ir_modules(new_module_info_plt)
          |> then(&Compiler.build_missing_ir!(ir_plt, &1))

          runtime_entry_file_path =
            Compiler.create_runtime_entry_file(
              runtime_mfas,
              ir_plt,
              encode_plt,
              async_mfas,
              app_versions,
              entry_file_opts
            )

          [{nil, runtime_entry_file_path, "runtime"}]
        end

      Cache.put_app_versions(app_versions)
      Cache.put_encoding_inputs(encoding_inputs)
      Cache.put_module_metadata(module_metadata)
      Cache.put_template_modules(template_modules)

      # The kept runtime state describes the bundle this compile replaces. A compile that fails
      # during the bundling leaves the next one diffing against the infos kept below, which show no
      # edit, so the state is forgotten here: without it the next compile rebuilds the runtime.
      if runtime_entry_files_info != [], do: Cache.put_runtime(nil)

      # The after picture, for the first compile in the next VM: the bundles on disk, what they were
      # built from, and the pages this compile is about to build, pending. Written before the before
      # picture, so that a compile that dies between the two leaves the pending pages next to the
      # infos they were computed from, or an older picture; either way the next compile rebuilds
      # them. Written again once the batches are done.
      dump_compile_state(before_dumped_at, compile_state_dump_path, module_info_plt_dump_path)

      dump_before_picture(before_dumped_at, call_graph, new_module_info_plt,
        call_graph_dump_path: call_graph_dump_path,
        graph_unchanged?: graph_unchanged?,
        infos_changed?: infos_changed?,
        module_info_plt_dump_path: module_info_plt_dump_path
      )

      # The dump time is kept with the infos, since the reuse guard compares them against it (see
      # Hologram.Compiler.Cache). After everything that patches the IR PLT and the call graph, so
      # that a compile that fails there leaves the before picture of the last finished one, against
      # which the partly patched IR PLT and call graph are patched again. Before the bundling, so
      # that a compile that fails there leaves this picture, and the next compile rebuilds the pages
      # it left pending.
      module_info_dumped_at = Compiler.module_info_dumped_at(module_info_plt_dump_path)

      Cache.put_module_infos(module_info_dumped_at, editable_modules)

      old_build_static_artifacts =
        opts[:static_dir]
        |> File.ls!()
        |> Enum.map(fn file_name -> Path.join(opts[:static_dir], file_name) end)

      forget_removed_pages(cache.pages_plt, page_modules)

      # A kept bundle is the file an earlier compile wrote, with the digest it recorded, so it
      # belongs in the page digest PLT and among the artifacts the cleanup below keeps. So does the
      # bundle a page still to rebuild had: it is served until its new one replaces it, which is
      # never when the compile stops before the page's batch.
      bundles =
        %{
          pages: initial_page_bundles_info(kept_pages, old_page_states, opts[:static_dir]),
          runtime: if(runtime_entry_files_info == [], do: cache.runtime.bundle_info)
        }

      # The links a page's last built state found, or its own listing found for a page with no
      # state. The scheduler reads the open pages' links only, and an open page's links move only
      # by the edit at hand.
      links = Compiler.list_page_links(modules_by_page, page_modules)

      batch_context = %{
        # The server callback analyses the batches compute, each templatable's once, whichever
        # batch reaches it first. Stopped with the supervisor.
        analyses: PLT.start(supervisor: sup),
        app_versions: app_versions,
        async_mfas: async_mfas,
        call_graph: call_graph_for_pages,
        client_config: client_config,
        encode_plt: encode_plt,
        entry_file_opts: entry_file_opts,
        gate: gate,
        ir_plt: ir_plt,
        links: links,
        listed_mfas_by_page: Map.new(unrecorded_mfas_by_page),
        module_info_plt: new_module_info_plt,
        old_runtime_bundle_info: cache.runtime && cache.runtime.bundle_info,
        opts: opts,
        read_graph: nil,
        runtime_js_binding_modules: runtime_js_binding_modules,
        runtime_mfas: runtime_mfas,
        supervisor: sup
      }

      dump_page_digest_plt(bundles, batch_context)

      remaining_pages = MapSet.new(pages_to_rebuild)

      bundles =
        build_batches(remaining_pages, runtime_entry_files_info, bundles, batch_context)

      # The pages built are in their states now, and no longer pending. The module info dump on disk
      # is the one this compile wrote or kept, so only a change of the state writes it.
      dump_compile_state(
        module_info_dumped_at,
        compile_state_dump_path,
        module_info_plt_dump_path
      )

      # Whatever ended the batches, the static dir keeps the bundles the page digest PLT names, and
      # the runtime bundle.
      named_build_static_artifacts =
        [bundles.runtime | Map.values(bundles.pages)]
        |> Enum.reject(&is_nil/1)
        |> Enum.flat_map(fn info -> [info.static_bundle_path, info.static_source_map_path] end)

      Enum.each(old_build_static_artifacts -- named_build_static_artifacts, &File.rm/1)

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
  # any of their versions (see Hologram.Compiler.app_versions_changed?/2). Unless the walk built
  # modules into the graph: one of them can belong to an application the graph did not reach before.
  defp build_app_versions(nil, call_graph, _module_digests_diff, _built_modules) do
    Compiler.build_app_versions(call_graph)
  end

  defp build_app_versions(kept_app_versions, call_graph, module_digests_diff, built_modules) do
    if built_modules != [] or
         Compiler.app_versions_changed?(module_digests_diff, Reflection.otp_app()) do
      Compiler.build_app_versions(call_graph)
    else
      kept_app_versions
    end
  end

  # The pages graph is shared with the batches once, and only when a page is left to list: the
  # runtime alone reads no page's reach, and a page listed before the batches has its list already.
  # So a compile with nothing to rebuild neither waits for the pages graph nor copies it.
  defp build_batches(remaining_pages, runtime_entry_files_info, bundles, context) do
    if Enum.all?(remaining_pages, &Map.has_key?(context.listed_mfas_by_page, &1)) do
      build_page_batches(remaining_pages, runtime_entry_files_info, bundles, context)
    else
      CallGraph.with_shared_graph(context.call_graph, fn read_graph ->
        build_page_batches(
          remaining_pages,
          runtime_entry_files_info,
          bundles,
          %{context | read_graph: read_graph}
        )
      end)
    end
  end

  # Returns the module info PLT of this compile, which is the cache's, the module digests diff, and
  # whether any entry changed. A cold compile reads every module against the dump, diffs the two
  # PLTs, copies the result into the cache's PLT, once, and compares the two PLTs' entries. A warm
  # one brings the cache's PLT in line in place, reading the modules the compiler reported among the
  # beams a save can rewrite, and takes the diff from that scan (see
  # Hologram.Compiler.patch_module_info_plt!/5). The cache holds the editable modules only between
  # two finished compiles, so nil means cold.
  defp build_module_info_plt(
         %{editable_modules: nil} = cache,
         old_plt,
         dumped_at,
         _editable_beams,
         _compiled_modules,
         sup
       ) do
    new_plt = Compiler.build_module_info_plt!(old_plt, dumped_at, supervisor: sup)
    module_digests_diff = Compiler.diff_module_info_plts(old_plt, new_plt)
    new_infos = PLT.get_all(new_plt)

    PLT.put(cache.module_info_plt, Map.to_list(new_infos))

    # An entry whose mtime moved but whose digest did not is a change the diff does not show, but
    # the dump must record it, or the next scan reads that beam again.
    {cache.module_info_plt, module_digests_diff, new_infos != PLT.get_all(old_plt)}
  end

  defp build_module_info_plt(cache, _old_plt, dumped_at, editable_beams, compiled_modules, _sup) do
    {module_digests_diff, infos_changed?} =
      Compiler.patch_module_info_plt!(
        cache.module_info_plt,
        dumped_at,
        cache.editable_modules,
        editable_beams,
        compiled_modules
      )

    {cache.module_info_plt, module_digests_diff, infos_changed?}
  end

  # Built once per VM when client stack traces are on, then patched with each compile's diff. Nothing
  # kept, or stack traces just turned on: built in full.
  defp build_module_metadata(kept_metadata, module_digests_diff, module_info_plt) do
    cond do
      not Hologram.client_stacktraces?() ->
        nil

      kept_metadata == nil ->
        Compiler.build_module_metadata(module_info_plt)

      true ->
        Compiler.patch_module_metadata(kept_metadata, module_digests_diff, module_info_plt)
    end
  end

  # Builds the pages still to rebuild in the batches the :next_batch option asks for, and the runtime
  # with the first one, and returns the bundles the page digest PLT names once the batches stop: the
  # ones built, and for the pages the batches did not get to, the ones they had. The runtime is built
  # even when the first answer is :stop, since the pages kept and the pages built both load it.
  defp build_page_batches(remaining_pages, runtime_entry_files_info, bundles, context) do
    case next_batch(remaining_pages, context) do
      :stop ->
        bundle_batch([], runtime_entry_files_info, bundles, context)

      page_modules ->
        new_bundles = bundle_batch(page_modules, runtime_entry_files_info, bundles, context)
        new_remaining_pages = MapSet.difference(remaining_pages, MapSet.new(page_modules))

        build_page_batches(new_remaining_pages, [], new_bundles, context)
    end
  end

  # The graph the pages are listed on: the runtime's copy without the runtime's MFAs, since every page
  # leaves out what the runtime bundle carries. None while there is no runtime copy (see
  # build_runtime_graph/3 and ensure_pages_graph/5).
  defp build_pages_graph(nil, _runtime_mfas), do: nil

  defp build_pages_graph(call_graph_for_runtime, runtime_mfas) do
    CallGraph.remove_runtime_mfas!(call_graph_for_runtime, runtime_mfas)
  end

  # The copy of the graph the runtime's MFAs are listed on, without the manually ported MFAs. None
  # when the runtime's MFAs are kept (see runtime_kept?/3): nothing lists them then.
  defp build_runtime_graph(_call_graph, true, _sup), do: nil

  defp build_runtime_graph(call_graph, false, sup) do
    call_graph
    |> CallGraph.clone(supervisor: sup)
    # DEFER: In case the list of manually ported MFAs grows to ~32 vertices,
    # consider using similar strategy to CallGraph.remove_runtime_mfas!/2
    # or implement opts param for Digraph.remove_vertices/2 to allow rebuilding the graph.
    |> CallGraph.remove_manually_ported_mfas()
  end

  # Builds the given pages, and the runtime when its entry file is given, and records them: their
  # states in the cache, the page digest PLT that names them, and the pages no longer pending. Then
  # the :bundles_built option is told what was built, the runtime first.
  defp bundle_batch([], [], bundles, _context), do: bundles

  defp bundle_batch(page_modules, runtime_entry_files_info, bundles, context) do
    batch_mfas_by_page = list_batch_mfas(page_modules, context)

    page_entry_files_info =
      batch_mfas_by_page
      |> Compiler.create_page_entry_files(
        context.ir_plt,
        context.encode_plt,
        context.async_mfas,
        context.runtime_js_binding_modules,
        context.entry_file_opts
      )
      |> Enum.map(fn {page_module, entry_file_path} -> {page_module, entry_file_path, "page"} end)

    built_bundles_info =
      Compiler.bundle(runtime_entry_files_info ++ page_entry_files_info, context.opts)

    keep_built_bundles(built_bundles_info, Map.new(batch_mfas_by_page), context)

    new_bundles = put_built_bundles_info(bundles, built_bundles_info, context)
    dump_page_digest_plt(new_bundles, context)
    Cache.delete_pending_pages(page_modules)

    built_entries =
      if runtime_entry_files_info == [], do: page_modules, else: [:runtime | page_modules]

    context.opts[:bundles_built].(built_entries)

    new_bundles
  end

  defp compile_with_lock(opts) do
    lock_path = Path.join(opts[:build_dir], Reflection.compiler_lock_file_name())

    with_lock(lock_path, fn ->
      compile(opts)
    end)
  end

  # The call graph and the module infos are the before picture of the next VM's first compile (see
  # load_before_state/4). While both dumps on disk are the ones this VM wrote or loaded (the module
  # info dump's mtime is the given one), the graph dump describes this graph when the graph is
  # unchanged, and the module info dump these infos when the scan changed no entry; each is written
  # only when it would say something else. The graph changes only with the infos, so a graph dump is
  # never written without the module info dump. Another VM's dump written meanwhile (the mtime
  # moved), or a deleted graph dump, is written over. The first compile in a VM loaded both under
  # the compiler lock, so they are its own too; a build dir with no module info dump has none to
  # own, and one with a module info dump but no graph dump loaded neither, so both are written then.
  defp dump_before_picture(dumped_at, call_graph, module_info_plt, opts) do
    own_dumps? = own_dumps?(dumped_at, opts[:module_info_plt_dump_path])

    if not (opts[:graph_unchanged?] and own_dumps? and File.exists?(opts[:call_graph_dump_path])) do
      CallGraph.dump(call_graph, opts[:call_graph_dump_path])
    end

    if opts[:infos_changed?] or not own_dumps? do
      PLT.dump(module_info_plt, opts[:module_info_plt_dump_path])
    end
  end

  # The compile state is written when it moved since this VM last wrote or loaded it, and whenever
  # the dumps on disk are not the given mtime's: another VM's compile state may be there (see
  # own_dumps?/2).
  defp dump_compile_state(dumped_at, compile_state_dump_path, module_info_plt_dump_path) do
    Cache.dump_compile_state(
      compile_state_dump_path,
      not own_dumps?(dumped_at, module_info_plt_dump_path)
    )
  end

  # The page digest PLT is dumped after every batch, so that the build dir names the bundles on disk
  # whenever the batches stop.
  defp dump_page_digest_plt(bundles, context) do
    {page_digest_plt, page_digest_plt_dump_path} =
      bundles.pages
      |> Map.values()
      |> Compiler.build_page_digest_plt(
        Keyword.put(context.opts, :supervisor, context.supervisor)
      )

    PLT.dump(page_digest_plt, page_digest_plt_dump_path)
    PLT.stop(page_digest_plt)
  end

  # The pages graph of a compile that kept the runtime's MFAs, made once a page is left to rebuild.
  defp ensure_pages_graph(nil, _call_graph, _runtime_mfas, [], _sup), do: nil

  defp ensure_pages_graph(nil, call_graph, runtime_mfas, _pages_to_rebuild, sup) do
    call_graph
    |> build_runtime_graph(false, sup)
    |> build_pages_graph(runtime_mfas)
  end

  defp ensure_pages_graph(call_graph_for_pages, _call_graph, _runtime_mfas, _pages, _sup) do
    call_graph_for_pages
  end

  # No state for a page that no longer exists, whose bundle the artifact cleanup deletes.
  defp forget_removed_pages(pages_plt, page_modules) do
    pages_plt
    |> PLT.keys()
    |> Kernel.--(page_modules)
    |> Enum.each(&Cache.delete_page/1)
  end

  # The bundle of each kept page, and the bundle each page still to rebuild had, if it had one that
  # can still be served: one whose file is gone, or that belongs to another static dir, would have
  # the page digest PLT name a bundle this static dir does not have.
  defp initial_page_bundles_info(kept_pages, old_page_states, static_dir) do
    kept_page_bundles_info =
      Map.new(kept_pages, fn {page_module, page_state} ->
        {page_module, page_state.bundle_info}
      end)

    Enum.reduce(old_page_states, kept_page_bundles_info, fn {page_module, page_state}, acc ->
      if Compiler.usable_bundle?(page_state.bundle_info, static_dir) do
        Map.put(acc, page_module, page_state.bundle_info)
      else
        acc
      end
    end)
  end

  # Records what a batch built, so that the next compile can reuse the bundles of the pages an edit
  # does not reach: a state per page bundle it wrote, and the runtime's inputs with its bundle.
  defp keep_built_bundles(built_bundles_info, mfas_by_page, context) do
    Enum.each(built_bundles_info, fn
      %{bundle_name: "page", entry_name: page_module} = bundle_info ->
        mfas = mfas_by_page[page_module]

        Cache.put_page(
          page_module,
          %{bundle_info: bundle_info, modules: page_state_modules(mfas)},
          mfas
        )

      %{bundle_name: "runtime"} = bundle_info ->
        Cache.put_runtime(%{
          app_versions: context.app_versions,
          bundle_info: bundle_info,
          client_config: context.client_config,
          js_binding_modules: context.runtime_js_binding_modules,
          mfas: context.runtime_mfas,
          dynamic_calls: context.gate.runtime
        })
    end)
  end

  # The kept bundles stay while the inputs are the ones they were built with. No inputs kept means no
  # bundles kept either (the first compile in a VM). The cache's PLTs are emptied in place, so the
  # snapshot's references hold; the fields the cache forgets are forgotten in the snapshot too.
  defp keep_bundle_inputs(%{bundle_inputs: kept_bundle_inputs} = cache, bundle_inputs)
       when kept_bundle_inputs in [nil, bundle_inputs] do
    Cache.put_bundle_inputs(bundle_inputs)
    cache
  end

  defp keep_bundle_inputs(cache, bundle_inputs) do
    Cache.forget_bundles()
    Cache.put_bundle_inputs(bundle_inputs)

    %{
      cache
      | encoding_inputs: nil,
        js_input_paths: MapSet.new(),
        pending_pages: MapSet.new(),
        runtime: nil,
        template_modules: nil
    }
  end

  # The runtime bundle carries the functions every page leaves out, so it is rebuilt when its MFAs,
  # the JS imports it registers or the app versions it names differ from the kept ones, and when a
  # module of those MFAs was edited: its functions are in the bundle, so their code is too. It is
  # rebuilt too when a file its bundle read changed (see Hologram.Compiler.js_inputs_changed?/2),
  # and when the client config it sets differs from this compile's. Both of its files are required,
  # since nothing else in the compile would recreate a missing source map.
  defp keep_runtime_bundle?(nil, _reaching_modules, _inputs), do: false

  defp keep_runtime_bundle?(kept_runtime, reaching_modules, inputs) do
    not Compiler.runtime_changed?(
      kept_runtime,
      inputs[:mfas],
      inputs[:js_binding_modules],
      inputs[:app_versions]
    ) and
      kept_runtime.client_config == inputs[:client_config] and
      not Compiler.js_inputs_changed?(
        kept_runtime.bundle_info.js_inputs,
        inputs[:js_fingerprints]
      ) and
      runtime_modules_untouched?(inputs[:mfas], reaching_modules) and
      Path.dirname(kept_runtime.bundle_info.static_bundle_path) == inputs[:static_dir] and
      File.exists?(kept_runtime.bundle_info.static_bundle_path) and
      File.exists?(kept_runtime.bundle_info.static_source_map_path)
  end

  # The first compile in a VM validated every templatable. A later one updates the kept entries with
  # the ones it validated, and drops the entries of modules that are no longer templatables (removed,
  # or edited into something else).
  defp keep_template_modules(nil, _templatable_modules, validated_template_modules) do
    validated_template_modules
  end

  defp keep_template_modules(
         kept_template_modules,
         templatable_modules,
         validated_template_modules
       ) do
    kept_template_modules
    |> Map.take(templatable_modules)
    |> Map.merge(validated_template_modules)
  end

  defp runtime_modules_untouched?(runtime_mfas, reaching_modules) do
    runtime_mfas
    |> page_state_modules()
    |> MapSet.disjoint?(reaching_modules)
  end

  # :stop when no page is left to build too, so that a runtime still to build is built alone.
  defp next_batch(remaining_pages, context) do
    if MapSet.size(remaining_pages) == 0 do
      :stop
    else
      remaining_pages
      |> context.opts[:next_batch].(context.links)
      |> validate_batch!(remaining_pages)
    end
  end

  # The runtime bundle is found by scanning the static dir rather than through the page digest PLT, so
  # the one it replaces is deleted as soon as it is written: a registry reload between two batches
  # could otherwise find the old one. A page's old bundle stays until the cleanup at the end.
  defp put_built_bundles_info(bundles, built_bundles_info, context) do
    Enum.reduce(built_bundles_info, bundles, fn
      %{bundle_name: "page", entry_name: page_module} = bundle_info, acc ->
        %{acc | pages: Map.put(acc.pages, page_module, bundle_info)}

      %{bundle_name: "runtime"} = bundle_info, acc ->
        remove_replaced_bundle(context.old_runtime_bundle_info, bundle_info)
        %{acc | runtime: bundle_info}
    end)
  end

  # Whether the module info dump on disk is the one the given mtime belongs to: the one this VM
  # wrote last, or the one the first compile in a VM loaded, under the compiler lock, so that
  # nothing wrote it since. No dump and no mtime count as the same.
  defp own_dumps?(dumped_at, module_info_plt_dump_path) do
    Compiler.module_info_dumped_at(module_info_plt_dump_path) == dumped_at
  end

  defp page_state_modules(mfas) do
    mfas
    |> Enum.map(fn {module, _function, _arity} -> module end)
    |> MapSet.new()
  end

  # With the inputs unchanged, the edited modules' encodings are dropped and the rest are kept; a
  # removed module's go with the delete that follows, with the modules the IR prune drops. Changed
  # inputs, or none kept (a cold compile), empty the PLT: a change in the async MFAs can change the
  # JavaScript of functions in modules the edit did not touch, the callers of a function that starts
  # or stops awaiting, so everything is encoded again for that one compile.
  defp patch_encode_plt(encode_plt, kept_inputs, inputs, module_digests_diff) do
    if kept_inputs == inputs do
      Compiler.delete_module_encodings(encode_plt, module_digests_diff.edited_modules)
    else
      PLT.reset(encode_plt)
    end
  end

  defp runtime_js_bindings_changed?(nil, _js_binding_modules), do: false

  defp runtime_js_bindings_changed?(kept_runtime, js_binding_modules) do
    kept_runtime.js_binding_modules != js_binding_modules
  end

  # The runtime's MFAs and the app versions are derived from the graph alone, so a compile that left
  # the graph as it was keeps them, unless a dependency outside the graph was edited, which can move
  # a version (see Hologram.Compiler.app_versions_changed?/2). With no runtime state kept (the first
  # compile in a VM, or one after a compile that failed while bundling) they are listed again.
  defp runtime_kept?(nil, _graph_unchanged?, _module_digests_diff), do: false

  defp runtime_kept?(_kept_runtime, graph_unchanged?, module_digests_diff) do
    graph_unchanged? and
      not Compiler.app_versions_changed?(module_digests_diff, Reflection.otp_app())
  end

  defp runtime_dynamic_calls_changed?(nil, _runtime_dynamic_calls), do: false

  # The page callers of the exposed runtime functions are left out: a page whose reach gains or
  # loses one had a module it reaches edited, and is rebuilt for that, and a page that does not
  # reach it lists the same MFAs either way.
  defp runtime_dynamic_calls_changed?(kept_runtime, runtime_dynamic_calls) do
    Map.take(kept_runtime.dynamic_calls, [:exposed, :open]) !=
      Map.take(runtime_dynamic_calls, [:exposed, :open])
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

  # The async MFAs are a walk of the graph, so a compile that left the graph as it was finds the ones
  # the last finished compile kept with its encoding inputs. The first compile in a VM has none kept.
  defp list_async_mfas(%{async_mfas: async_mfas}, _call_graph, true), do: async_mfas

  defp list_async_mfas(_kept_inputs, call_graph, _graph_unchanged?) do
    CallGraph.list_async_mfas(call_graph)
  end

  # A batch's pages are listed here rather than before the first batch, so the open tab's page is
  # bundled as soon as its own list is done; a page listed before the batches, one with no state,
  # reuses that list. The IR the pages' entry files read is built right after, what an earlier
  # compile kept being there already. A batch of the runtime alone lists nothing.
  defp list_batch_mfas([], _context), do: []

  defp list_batch_mfas(page_modules, context) do
    {listed_pages, unlisted_pages} =
      Enum.split_with(page_modules, &Map.has_key?(context.listed_mfas_by_page, &1))

    listed_mfas_by_page = Enum.map(listed_pages, &{&1, context.listed_mfas_by_page[&1]})

    mfas_by_page =
      unlisted_pages
      |> Compiler.list_mfas_by_page(context.read_graph, context.analyses, context.module_info_plt,
        gate: context.gate
      )
      |> Enum.concat(listed_mfas_by_page)

    ir_modules =
      mfas_by_page
      |> Enum.flat_map(fn {_page_module, mfas} -> mfas end)
      |> Compiler.list_ir_modules(context.module_info_plt)

    Compiler.build_missing_ir!(context.ir_plt, ir_modules)

    mfas_by_page
  end

  # The states of the pages to rebuild that an earlier compile built. Each still serves its bundle
  # until its new one is written, and its modules say what IR to keep and which pages it links to.
  defp list_old_page_states(page_modules, pages_plt) do
    Enum.flat_map(page_modules, fn page_module ->
      case PLT.get(pages_plt, page_module) do
        {:ok, page_state} -> [{page_module, page_state}]
        :error -> []
      end
    end)
  end

  # What the runtime's dynamic calls open is taken from the runtime's MFAs, so a compile that kept
  # them (see runtime_kept?/3) keeps it too.
  defp list_runtime_dynamic_calls(kept_runtime, _call_graph, _runtime_mfas, _ir_plt, true),
    do: kept_runtime.dynamic_calls

  defp list_runtime_dynamic_calls(_kept_runtime, call_graph, runtime_mfas, ir_plt, false) do
    CallGraph.runtime_dynamic_calls(call_graph, runtime_mfas, ir_plt)
  end

  # The runtime's MFAs are a walk of the graph, so a compile that kept them (see runtime_kept?/3)
  # finds the ones the runtime bundle on disk was built from.
  defp list_runtime_mfas(kept_runtime, _call_graph, _page_modules, true), do: kept_runtime.mfas

  defp list_runtime_mfas(_kept_runtime, call_graph, page_modules, false) do
    CallGraph.list_runtime_mfas(call_graph, page_modules)
  end

  # Returns the cache, the module info PLT to diff against (the cache's own on a warm compile, which
  # the scan brings in line in place) and the dump time the module info reuse guard takes. The
  # kept module infos are the proof that the kept IR PLT and call graph are exactly in line with
  # them, whatever another VM wrote to the build dir since, and they are trusted only between two
  # finished compiles (the cache keeps the editable modules then). Without them (the first compile
  # in a VM, or after a failed one) the cache is emptied and the build dir is the before picture:
  # the graph comes from its dump and the module info dump written next to it says what changed. The
  # compile state dump next to them is the after picture, what the bundles on disk were built from.
  defp load_before_state(build_dir, call_graph_dump_path, compile_state_dump_path, sup) do
    case Cache.get() do
      %{editable_modules: nil} ->
        :ok = Cache.reset()
        cache = Cache.get()

        # The two dumps are one before picture, and the graph dump is never written without the
        # module info dump, so a module info dump without a graph dump is not a before picture:
        # diffing against it would report no changes and leave the empty graph with nothing to
        # patch. Neither is a graph dump of another dump version, which the graph does not load (see
        # CallGraph.load/2). Without a graph dump every module counts as added, of which the pages
        # and the broadcast callers are patched in, and the graph is grown from them (see
        # Hologram.Compiler.build_reach!/3).
        {module_info_plt, dumped_at} =
          with true <- File.exists?(call_graph_dump_path),
               :ok <- CallGraph.load(cache.call_graph, call_graph_dump_path) do
            # The after picture of the compile that wrote the before picture: the bundles it left and
            # what they were built from. Its page states are trusted only against the diff of these
            # module infos, which is why it is loaded here and not with a module info dump alone. A
            # dump of another version, or none, leaves every page to be built.
            maybe_load_compile_state(compile_state_dump_path)

            {plt, _dump_path, dumped_at} =
              Compiler.maybe_load_module_info_plt(build_dir, supervisor: sup)

            {plt, dumped_at}
          else
            _no_usable_dump -> {PLT.start(supervisor: sup), nil}
          end

        # Taken after the loads, so that the snapshot holds what was loaded.
        {Cache.get(), module_info_plt, dumped_at}

      cache ->
        # Cleared before anything is patched in place: a compile that dies mid-patch can leave the
        # kept graph without edges that only its callers would rebuild, and the kept infos half
        # scanned, so the next compile must start from the dumps rather than from a half-patched
        # graph. The infos are marked as kept again last, after the dumps.
        :ok = Cache.clear_module_infos()

        {cache, cache.module_info_plt, cache.dumped_at}
    end
  end

  # A dump of another version is not loaded (see Hologram.Compiler.Cache.load_compile_state/1): the
  # state stays empty, as it does with no dump.
  defp maybe_load_compile_state(compile_state_dump_path) do
    if File.exists?(compile_state_dump_path) do
      Cache.load_compile_state(compile_state_dump_path)
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

  # A digest names its bundle's content, so a rebuild that wrote the same content wrote the same file.
  defp remove_replaced_bundle(nil, _new_bundle_info), do: :ok

  defp remove_replaced_bundle(old_bundle_info, new_bundle_info) do
    if old_bundle_info.static_bundle_path != new_bundle_info.static_bundle_path do
      File.rm(old_bundle_info.static_bundle_path)
      File.rm(old_bundle_info.static_source_map_path)
    end

    :ok
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
  # The :next_batch option answers with pages to build now: some of the remaining ones, and at least
  # one, since an empty batch would ask again forever.
  defp validate_batch!(:stop, _remaining_pages), do: :stop

  defp validate_batch!([_page_module | _rest] = page_modules, remaining_pages) do
    unknown_pages = Enum.reject(page_modules, &MapSet.member?(remaining_pages, &1))

    if unknown_pages != [] do
      raise ArgumentError,
            "Hologram: the :next_batch option returned pages that are not left to build: " <>
              inspect(unknown_pages)
    end

    Enum.uniq(page_modules)
  end

  defp validate_batch!(batch, _remaining_pages) do
    raise ArgumentError,
          "Hologram: the :next_batch option must return a non-empty list of pages or :stop, got: " <>
            inspect(batch)
  end

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

  # Runs here rather than in each module's own compilation: every module is compiled by now, so a
  # used component's __props__/0 is simply callable, with no compile-time dependency on it and no
  # deadlock when a component renders itself. Only the templates an edit can affect are validated
  # (see Hologram.Compiler.list_templatables_to_validate/3), and the IR of the ones no page reaches is
  # built for that alone. Returns the modules each templatable's template uses, kept for the next
  # compile.
  defp validate_prop_usages(
         templatable_modules,
         module_digests_diff,
         kept_template_modules,
         ir_plt
       ) do
    modules_to_validate =
      Compiler.list_templatables_to_validate(
        templatable_modules,
        module_digests_diff,
        kept_template_modules
      )

    Compiler.build_missing_ir!(ir_plt, modules_to_validate)
    validated_template_modules = Compiler.validate_prop_usages(modules_to_validate, ir_plt)

    keep_template_modules(kept_template_modules, templatable_modules, validated_template_modules)
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
