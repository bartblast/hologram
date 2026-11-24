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
      for the next compile. The runtime bundle and the chunk bundles, when they are rebuilt, and
      the data model bundle, when it is written anew, are built with the first batch, or alone
      when the first answer is `:stop`. Defaults to every page in one batch.

    * `:bundles_built` - called after each batch is on disk and named by the page digest PLT dump,
      with the page modules built, preceded by `:runtime` when the runtime bundle was built, by
      `:data_model` when the data model bundles on disk changed and by `:chunks` when the chunk
      bundles were built, in that order. Called with `[:data_model]` alone when a compile builds
      nothing else but changes the data model bundles, and not at all when it builds and changes
      nothing. Defaults to doing nothing.

  ## Data model

  A compile validates the data model once its module info PLT is in line with the beams, before it
  derives or builds anything from the model. A caller that has work of its own to do on a valid
  model before the bundles are built (live reload, to bring the database schema in line), or that
  wants to hear of an invalid one, does it with two options:

    * `:data_model_failed` - called when the data model step fails, the validation or the
      `:data_model_ready` call, with the kind and the reason as a `catch` binds them (`:error` and
      the exception for a raise), before the failure is raised again. Defaults to doing nothing.

    * `:data_model_ready` - called once per compile, right after the validation, with the entity
      types and the roles. A compile that raises here builds nothing. Defaults to doing nothing.

    * `:index_needs_ready` - called once per compile, with no arguments, once the data layer is
      derived or kept, so its index needs dump is the one the queries give (live reload, to build
      the indexes they need). A compile that raises here builds nothing, and the next one keeps the
      data layer it derived and calls it again. Defaults to doing nothing.

  An invocation that never compiles (Hologram off in dev and test) validates the model from the
  beams instead, and only when the Elixir compile manifest of a loaded application moved since the
  last validation that passed in the same build dir, which leaves the data model inputs dump there
  (see `Hologram.Compiler.DataModelInputs`). A language server's build validates nothing.

  ## Build dir

  A compile leaves nine files in the build dir, so that the first compile in the next VM (the next
  `mix` command, say) reuses what this one built, and the running app reads what it derived:

    * the call graph dump and the module info dump - the before picture: the graph of what the
      pages reach and the module infos it was brought in line with, which the next compile diffs
      the beams against.

    * the compile state dump - the after picture: what each page, the runtime bundle and the
      chunk bundles were built from, the pages still to build, what the compile derived for the
      bundles and what the data layer was derived from. The next compile keeps the bundles the diff
      does not reach.

    * the page digest dump - the digest of each page's bundle, which the router serves.

    * the chunk registry dump - the chunks each struct type needs and the chunks each page
      preloads, which the server reads when it renders a page or encodes a value.

    * the compile inputs dump - what a compile with nothing to do is decided by, as the last compile
      that built every page saw it (see `Hologram.Compiler.CompileInputs`).

    * the page types dump - the synced types a sync session on each page fills first when a
      client connects.

    * the queries dump - the derived fields' definitions, the synced types and whether a page checks
      permissions on the client, which the renderer and the sync layer read.

    * the index needs dump - the access needs of the statements the server runs, which the database
      converges its indexes to (see `Hologram.DB.IndexPlan.plan/2`).

  The bundles go to the build dir too, to its static dir (see `Hologram.Reflection.bundles_dir/0`),
  which `Hologram.Router` serves them from. Each build env has a build dir of its own, so a compile
  in one env leaves the bundles another env serves alone.

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
  alias Hologram.Commons.TaskUtils
  alias Hologram.Compiler
  alias Hologram.Compiler.Cache
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.CompileInputs
  alias Hologram.Compiler.DataModelInputs
  alias Hologram.Compiler.Tracer
  alias Hologram.DB.IndexPlan
  alias Hologram.DB.Mapper
  alias Hologram.Entity.Derived
  alias Hologram.Entity.Derived.Validator, as: DerivedValidator
  alias Hologram.Entity.Model
  alias Hologram.Entity.Validator, as: EntityValidator
  alias Hologram.Migration.Loader
  alias Hologram.Policy
  alias Hologram.Policy.Edges
  alias Hologram.Policy.Validator, as: PolicyValidator
  alias Hologram.Reflection
  alias Hologram.Sync.Rules

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

  # What a batch after the first is given of what every page shares: nothing, since the first one
  # built it (see build_page_batches/4).
  @later_batch_shared %{data_model?: false, entry_files_info: []}

  @ls_build_dirs [".elixir_ls", ".elixir-tools", ".expert", ".lexical"]

  @impl Mix.Task.Compiler
  # If the options are strings, it means that the task was executed directly by the Elixir compiler.
  def run([hd | _tail]) when is_binary(hd) do
    run(build_default_opts())
  end

  @doc """
  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/mix/tasks/compile.hologram/README.md
  """
  @impl Mix.Task.Compiler
  def run(opts) do
    opts = Keyword.merge(build_default_opts(), opts)

    # Every build, a release's included - the elixirc_paths are the current environment's. A migration
    # beam the build reuses from another environment never had its draft refused by its compile.
    if not language_server_build?(opts) do
      Loader.validate_migrations_compiled!(opts[:app_dir])
      # credo:disable-for-next-line Credo.Check.Warning.MixEnv
      Loader.validate_project_resolved!(Mix.env())
    end

    result =
      cond do
        opts[:force?] ->
          opts
          |> put_first_compile()
          |> compile_with_lock()

        # A language server builds in a build root of its own, for its diagnostics: the data model
        # is validated by the developer's own mix invocations, not here.
        language_server_build?(opts) ->
          :noop

        # This invocation never compiles, so the data model is validated here, from the beams, when
        # a module may have changed since the last validation.
        not compiler_enabled?() ->
          validate_uncompiled_data_model!(opts)
          :noop

        true ->
          opts = put_first_compile(opts)

          # No module changed since the compile that validated the data model.
          if nothing_changed?(opts) do
            see_module_info_dump(opts)
            :noop
          else
            compile_with_lock(opts)
          end
      end

    # TODO: Remove this block together with refresh_umbrella_app_manifests/0
    # (see the removal note there), and inline the cond above back into the
    # function body - the result binding exists only to run this afterwards.
    if not language_server_build?(opts) do
      refresh_umbrella_app_manifests()
    end

    result
  end

  defp beam_dir(beam_path) do
    beam_path
    |> to_string()
    |> Path.dirname()
    |> Path.expand()
  end

  defp build_default_opts do
    assets_dir = Path.join(Reflection.hologram_dep_dir(), "assets")
    build_dir = Reflection.build_dir()
    node_modules_path = Path.join(assets_dir, "node_modules")

    [
      app_dir: Reflection.otp_app_dir(),
      assets_dir: assets_dir,
      build_dir: build_dir,
      build_lib_dir: Path.join(Mix.Project.build_path(), "lib"),
      bundles_built: fn _built -> :ok end,
      data_model_failed: fn _kind, _reason -> :ok end,
      data_model_ready: fn _entity_types, _role_modules -> :ok end,
      index_needs_ready: fn -> :ok end,
      js_dir: Path.join(assets_dir, "js"),
      # TODO: Remove together with the removal in compile/1.
      legacy_bundles_dir: Path.join(Reflection.otp_app_static_dir(), "hologram"),
      next_batch: fn remaining_pages, _links -> MapSet.to_list(remaining_pages) end,
      node_modules_path: node_modules_path,
      static_dir: Reflection.bundles_dir(),
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

      # The dir in the app's static dir that the bundles went to before they moved to the build dir.
      # Removed so that `mix phx.digest` stops digesting the old bundles and releases stop shipping
      # them.
      # TODO: Remove once apps have had a release to upgrade through.
      File.rm_rf(opts[:legacy_bundles_dir])

      # Every build env shares the JS deps, like Mix's deps, so their install takes a lock of the
      # assets dir as well, which a compile in another env waits on. Taken under the compiler lock,
      # and nothing that holds it waits on a compiler lock, so the two can't deadlock.
      install_lock_path = Path.join(assets_dir, Reflection.js_deps_install_lock_file_name())

      with_lock(install_lock_path, "JS deps install", fn ->
        Compiler.maybe_install_js_deps(assets_dir)
      end)

      # Resolved once the deps are installed: on the first compile in a fresh checkout there is no
      # node_modules before the install, and the binary of esbuild's platform package is in it.
      opts =
        Keyword.put_new_lazy(opts, :esbuild_bin_path, fn ->
          Compiler.esbuild_bin_path(opts[:node_modules_path])
        end)

      module_info_plt_dump_path =
        Path.join(build_dir, Reflection.module_info_plt_dump_file_name())

      call_graph_dump_path = Path.join(build_dir, Reflection.call_graph_dump_file_name())

      compile_inputs_dump_path =
        Path.join(build_dir, Reflection.compile_inputs_dump_file_name())

      # Gone until this compile finishes with every page built, so that a compile that fails, having
      # replaced some bundles, leaves the next one nothing to skip on.
      File.rm(compile_inputs_dump_path)

      compile_state_dump_path =
        Path.join(build_dir, Reflection.compile_state_dump_file_name())

      # The IR PLT and the call graph are kept between compiles (see Hologram.Compiler.Cache), and
      # the module infos they were last brought in line with, with the modules whose beams a save
      # can rewrite, are the before picture. The IR PLT holds the IR this compile reads, no more:
      # the modules the graph patch rebuilds first, then the ones the walk reaches, then the rest
      # once the graph says what is reachable. The dump stamp is the module info dump's the before
      # picture came from: the one this VM kept, or the one the first compile in a VM loaded. Its
      # mtime is the dump time.
      {cache, old_module_info_plt, before_dump_stamp} =
        load_before_state(build_dir, call_graph_dump_path, compile_state_dump_path, sup)

      before_dumped_at = stamp_mtime(before_dump_stamp)

      # Listed with the scan, so that the modules kept as editable and the module infos kept with
      # them describe the same moment.
      editable_beams = Reflection.list_editable_beams()
      editable_modules = MapSet.new(editable_beams, fn {module, _beam_path} -> module end)

      # Read on a cold compile too, so that the modules its full scan covers are forgotten.
      {compiled_modules, compiled_records} =
        editable_beams
        |> Map.new()
        |> Tracer.peek()

      {new_module_info_plt, module_digests_diff, infos_changed?, previous_infos} =
        build_module_info_plt(
          cache,
          old_module_info_plt,
          before_dumped_at,
          editable_beams,
          compiled_modules,
          sup
        )

      # Before anything below calls into the changed modules.
      unload_replaced_modules(module_digests_diff, compiled_modules, %{
        before_dump_stamp: before_dump_stamp,
        cache: cache,
        editable_modules: editable_modules,
        first_compile?: opts[:first_compile?]
      })

      # Seen: a later cold compile that finds this dump needs no check of every loaded module.
      Cache.put_seen_dump_stamp(before_dump_stamp)

      # What a compile that fails on the data model goes back to. The snapshot was taken before the
      # kept state was marked as not to be trusted.
      before = %{
        dump_stamp: before_dump_stamp,
        editable_modules: cache.editable_modules,
        previous_infos: previous_infos
      }

      # Before anything is derived or built from the data model.
      load_data_model!(new_module_info_plt, before, opts)

      # Only now: a compile that fails on the data model leaves the records, so the next one reads
      # the same modules again.
      Tracer.forget(compiled_records)

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

      component_modules = list_component_modules(new_module_info_plt, opts)

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

      # What the chunks hold is derived from the graph alone, so a compile that left the graph as it
      # was keeps it. With no chunk state kept (after a change of the bundle inputs, or after a
      # compile that failed while bundling) it is derived again.
      chunk_analysis_kept? = graph_unchanged? and cache.chunks != nil

      # Grows it further by what the chunks hold and no page reaches: the struct functions of the
      # struct types no page's code names, their implementations, and what only those call. Before
      # the async MFAs and the app versions are taken, which read the whole graph.
      chunk_reach =
        build_chunk_reach(
          call_graph,
          ir_plt,
          page_modules,
          component_modules,
          chunk_analysis_kept?
        )

      # What the data layer kept of each page's reach that still holds, and the pages whose reach it
      # lists again, if it derives at all (see partition_kept_page_reach/4).
      impl_seeds = impl_seeds(cache.data_layer, call_graph, graph_unchanged?)

      new_impls =
        list_new_impls(
          module_digests_diff,
          new_module_info_plt,
          old_module_info_plt,
          previous_infos
        )

      data_layer_reaching_modules =
        data_layer_reaching_modules(reaching_modules, new_impls, new_module_info_plt)

      {kept_page_reach, pages_to_list} =
        partition_kept_page_reach(
          cache.data_layer,
          page_modules,
          impl_seeds,
          data_layer_reaching_modules
        )

      # The walks of the implementations of the types each kept page holds through rows that still
      # hold (see keep_held_impl_walks/3).
      kept_held_impl_walks =
        keep_held_impl_walks(cache.data_layer, kept_page_reach, data_layer_reaching_modules)

      # Whether the vocabulary the queries and the operation asks are judged against can have moved
      # (see data_model_changed?/2).
      data_model_changed? = data_model_changed?(module_digests_diff, new_module_info_plt)

      # Whether the kept derived definitions can be out of date (see derived_stale?/3).
      derived_stale? = derived_stale?(cache.data_layer, module_digests_diff, data_model_changed?)

      # The shapes of the queries the code writes, which the index needs are derived from (see
      # list_query_shapes/3).
      query_shapes =
        list_query_shapes(cache.data_layer, new_module_info_plt, module_digests_diff)

      # Must be computed before remove_manually_ported_mfas/1 strips the Task.await/1 vertex.
      async_mfas = list_async_mfas(cache.encoding_inputs, call_graph, graph_unchanged?)

      runtime_kept? = runtime_kept?(cache.runtime, graph_unchanged?, module_digests_diff)

      # What the data layer derives from the build (see derive_data_layer!/1) is kept whole while
      # the edit touches nothing it reads (see data_layer_kept?/3): its dumps are on disk from the
      # compile that derived it, and the data layer state holds the statement it rendered for the
      # data model bundle.
      data_layer_kept? =
        data_layer_kept?(
          cache.data_layer,
          %{
            data_model_changed?: data_model_changed?,
            derived_stale?: derived_stale?,
            held_impls_changed?:
              held_impls_changed?(
                cache.data_layer,
                Map.keys(kept_page_reach),
                kept_held_impl_walks,
                new_impls
              ),
            kept_page_reach: kept_page_reach,
            own_dumps?: own_dumps?(before_dump_stamp, module_info_plt_dump_path),
            pages_to_list: pages_to_list,
            query_shapes: query_shapes
          },
          opts
        )

      # The chunks' MFAs are listed on the runtime's copy too, and so is the data layer's reach of
      # every page it lists again, and of every page it walks for the types it holds through rows.
      runtime_graph_kept? =
        Enum.all?([runtime_kept?, chunk_analysis_kept?, pages_to_list == [], data_layer_kept?])

      call_graph_for_runtime = build_runtime_graph(call_graph, runtime_graph_kept?, sup)

      templatable_modules = page_modules ++ component_modules

      {template_modules, template_refs, ref_names_by_page} =
        validate_templates(
          templatable_modules,
          page_modules,
          module_digests_diff,
          cache,
          ir_plt,
          new_module_info_plt
        )

      # Listed once, from the module info PLT this compile brought in line with the beams: no beam
      # is read and no module is asked.
      entity_types = Reflection.list_entities(new_module_info_plt)

      # Before the IR prune, which drops the IR this builds for a caller no page reaches.
      maybe_validate_operations!(entity_types, call_graph, ir_plt, %{
        data_model_changed?: data_model_changed?,
        kept_data_layer: cache.data_layer,
        module_digests_diff: module_digests_diff
      })

      # The statement the data model bundle sets the client's data layer constants with and the
      # struct types a synced row can hold: from the derivation, or kept with the data layer it was
      # derived with.
      %{js: sync_constants_js, row_types: row_types} =
        data_layer_output(data_layer_kept?, %{
          call_graph: call_graph,
          call_graph_for_runtime: call_graph_for_runtime,
          derived_stale?: derived_stale?,
          entity_types: entity_types,
          impl_seeds: impl_seeds,
          ir_plt: ir_plt,
          kept_data_layer: cache.data_layer,
          kept_held_impl_walks: kept_held_impl_walks,
          kept_page_reach: kept_page_reach,
          module_info_plt: new_module_info_plt,
          opts: opts,
          pages_to_list: pages_to_list,
          query_shapes: query_shapes,
          supervisor: sup
        })

      # The types whose implementations every page preloads, in one chunk. They can move on an
      # unchanged graph, since a role module edit derives the data layer again without touching it,
      # and then the chunks are grouped again, on a runtime graph made for that if none was.
      held_types = MapSet.intersection(row_types, impl_types(cache.chunks, chunk_reach))
      chunk_analysis_kept? = chunk_analysis_kept?(chunk_analysis_kept?, cache.chunks, held_types)

      {chunk_reach, call_graph_for_runtime} =
        ensure_chunk_reach(chunk_reach, call_graph_for_runtime, chunk_analysis_kept?, %{
          call_graph: call_graph,
          component_modules: component_modules,
          ir_plt: ir_plt,
          page_modules: page_modules,
          supervisor: sup
        })

      # Taken again, since that walk can have found a type the kept chunks don't know of. What it
      # built has to reach the graph dump too.
      impl_types = impl_types(cache.chunks, chunk_reach)
      held_types = MapSet.intersection(row_types, impl_types)
      graph_unchanged? = graph_still_unchanged?(graph_unchanged?, chunk_reach)

      runtime_analysis = runtime_analysis(cache.runtime, call_graph_for_runtime, runtime_kept?)
      runtime_mfas = runtime_analysis.mfas

      # The MFAs of each chunk, by its signature, listed while the runtime graph still holds the
      # runtime's MFAs (build_pages_graph/2 below takes them out), and kept when the analysis is.
      chunk_mfas_by_signature =
        list_chunk_mfas_by_signature(
          cache.chunks,
          chunk_reach,
          call_graph_for_runtime,
          runtime_mfas,
          held_types
        )

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
          built_modules ++ chunk_built_modules(chunk_reach)
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
      # The chunks' modules are kept like the runtime's: their bundles are rendered from the same
      # IR and encodings.
      kept_modules =
        Compiler.list_kept_modules(
          runtime_mfas ++ chunk_mfas(chunk_mfas_by_signature),
          modules_by_page,
          new_module_info_plt
        )

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

      # The optional runtime subsystems this build ships (see runtime_subsystems/1), rendered into
      # the runtime entry file and kept with its bundle as one of its inputs.
      subsystems = runtime_subsystems(entity_types)

      # The data model bundle this build serves, none without the data layer: written or kept with
      # the first batch (see write_data_model_bundle/2). Asked for here, before any bundling, so
      # that a bundle over the size limit fails the compile before any bundle is written.
      data_model_bundle =
        Compiler.data_model_bundle(sync_constants_js, subsystems, opts[:static_dir])

      entry_file_opts =
        Keyword.merge(opts,
          module_info_plt: new_module_info_plt,
          module_metadata: module_metadata,
          ref_names_by_page: ref_names_by_page,
          subsystems: subsystems
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
             static_dir: opts[:static_dir],
             subsystems: subsystems
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

      chunk_entry_file_opts =
        Keyword.put(entry_file_opts, :runtime_js_binding_modules, runtime_js_binding_modules)

      # The chunks as bundled, by signature, with their sizes: the kept state's when the analysis is
      # kept, else folded from the listing (see Hologram.Compiler.fold_chunks/5).
      %{chunks: chunks, sizes: chunk_sizes} =
        fold_chunks(
          chunk_analysis_kept?,
          cache.chunks,
          chunk_mfas_by_signature,
          ir_plt,
          encode_plt,
          async_mfas,
          Keyword.merge(chunk_entry_file_opts,
            held_types: held_types,
            sizes:
              reusable_chunk_sizes(
                cache.chunks,
                reaching_modules,
                cache.encoding_inputs == encoding_inputs
              )
          )
        )

      kept_chunk_bundles_info =
        keep_chunk_bundles(cache.chunks, chunks, reaching_modules,
          js_bindings_changed?:
            runtime_js_bindings_changed?(cache.runtime, runtime_js_binding_modules),
          js_fingerprints: js_fingerprints,
          static_dir: opts[:static_dir]
        )

      chunks_to_build = Map.drop(chunks, Map.keys(kept_chunk_bundles_info))

      # The entry files are rendered before the batches like the runtime's, from IR built here: a
      # kept chunk reads none, and a chunk rebuilt on a kept analysis may read IR a new VM lacks.
      chunk_entry_files_info =
        create_chunk_entry_files(
          chunks_to_build,
          ir_plt,
          encode_plt,
          async_mfas,
          chunk_entry_file_opts
        )

      Cache.put_app_versions(app_versions)
      Cache.put_encoding_inputs(encoding_inputs)
      Cache.put_module_metadata(module_metadata)
      Cache.put_template_modules(template_modules)
      Cache.put_template_refs(template_refs)

      chunk_types = %{held_types: held_types, impl_types: impl_types}

      keep_chunk_state(kept_chunk_bundles_info, chunks, chunk_sizes, chunk_types)
      keep_runtime_state(cache.runtime, runtime_entry_files_info, runtime_dynamic_calls)

      # The after picture, for the first compile in the next VM: the bundles on disk, what they were
      # built from, and the pages this compile is about to build, pending. Written before the before
      # picture, so that a compile that dies between the two leaves the pending pages next to the
      # infos they were computed from, or an older picture; either way the next compile rebuilds
      # them. Written again once the batches are done.
      dump_compile_state(before_dump_stamp, compile_state_dump_path, module_info_plt_dump_path)

      dump_before_picture(before_dump_stamp, call_graph, new_module_info_plt,
        call_graph_dump_path: call_graph_dump_path,
        graph_unchanged?: graph_unchanged?,
        infos_changed?: infos_changed?,
        module_info_plt_dump_path: module_info_plt_dump_path
      )

      # The dump stamp is kept with the infos, since the reuse guard compares them against its mtime
      # (see Hologram.Compiler.Cache), and the next compile tells this dump from another VM's by it.
      # After everything that patches the IR PLT and the call graph, so that a compile that fails
      # there leaves the before picture of the last finished one, against which the partly patched
      # IR PLT and call graph are patched again. Before the bundling, so that a compile that fails
      # there leaves this picture, and the next compile rebuilds the pages it left pending.
      module_info_dump_stamp = Compiler.module_info_dump_stamp(module_info_plt_dump_path)

      Cache.put_module_infos(module_info_dump_stamp, editable_modules)

      # Once the data layer is derived or kept and this compile's before picture is written, so that
      # a compile failing here leaves the picture the data layer was derived against: the next one
      # keeps that data layer and calls this again. Before the bundling, like the data model hook.
      opts[:index_needs_ready].()

      old_build_static_artifacts =
        opts[:static_dir]
        |> File.ls!()
        |> Enum.map(fn file_name -> Path.join(opts[:static_dir], file_name) end)

      forget_removed_pages(cache.pages_plt, page_modules)

      # A kept bundle is the file an earlier compile wrote, with the digest it recorded, so it
      # belongs in the page digest PLT and among the artifacts the cleanup below keeps. So does the
      # bundle a page still to rebuild had: it is served until its new one replaces it, which is
      # never when the compile stops before the page's batch. The chunk bundles the kept state
      # names are served too until the first batch replaces the ones to rebuild. With them, the
      # struct types the client code of each page names, as its last built state recorded them,
      # which decide the chunks the page preloads.
      bundles =
        %{
          chunks:
            initial_chunk_bundles_info(cache.chunks, kept_chunk_bundles_info, chunks_to_build),
          page_chunk_types:
            Map.new(kept_pages ++ old_page_states, fn {page_module, page_state} ->
              {page_module, page_state.chunk_types}
            end),
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
        chunk_entry_files_info: chunk_entry_files_info,
        chunk_sizes: chunk_sizes,
        chunk_types: chunk_types,
        chunks: chunks,
        client_config: client_config,
        data_model_bundle: data_model_bundle,
        encode_plt: encode_plt,
        entry_file_opts: entry_file_opts,
        gate: gate,
        held_types: held_types,
        ir_plt: ir_plt,
        kept_chunk_bundles_info: kept_chunk_bundles_info,
        links: links,
        listed_mfas_by_page: Map.new(unrecorded_mfas_by_page),
        module_info_plt: new_module_info_plt,
        opts: opts,
        read_graph: nil,
        runtime_js_binding_modules: runtime_js_binding_modules,
        runtime_mfas: runtime_mfas,
        runtime_types: runtime_analysis.types,
        subsystems: subsystems,
        supervisor: sup
      }

      # The chunk registry names the chunks the kept state names until the first batch replaces
      # them, so a page served meanwhile is given chunks that are on disk.
      dump_chunk_registry_plt(bundles, batch_context)
      dump_page_digest_plt(bundles, batch_context)

      remaining_pages = MapSet.new(pages_to_rebuild)

      # What every page shares is bundled with the first batch.
      shared_entry_files_info =
        runtime_entry_files_info ++
          Enum.map(chunk_entry_files_info, fn {_signature, signature_digest, entry_file_path} ->
            {signature_digest, entry_file_path, "chunk"}
          end)

      bundles =
        build_batches(
          remaining_pages,
          %{data_model?: true, entry_files_info: shared_entry_files_info},
          bundles,
          batch_context
        )

      # The pages built are in their states now, and no longer pending. The module info dump on disk
      # is the one this compile wrote or kept, so only a change of the state writes it.
      dump_compile_state(
        module_info_dump_stamp,
        compile_state_dump_path,
        module_info_plt_dump_path
      )

      # Whatever ended the batches, the static dir keeps the bundles the page digest PLT names, the
      # runtime bundle, the data model bundle and the chunk bundles.
      served_bundles_info =
        Enum.reject(
          [bundles.runtime | Map.values(bundles.pages)] ++ Map.values(bundles.chunks),
          &is_nil/1
        )

      named_build_static_artifacts =
        served_bundles_info
        |> Enum.flat_map(fn info ->
          [
            info.static_bundle_path,
            Compiler.gzip_path(info.static_bundle_path),
            info.static_source_map_path
          ]
        end)
        |> Enum.concat(data_model_bundle_artifacts(data_model_bundle))

      Enum.each(old_build_static_artifacts -- named_build_static_artifacts, &File.rm/1)

      # The world as this compile leaves it, for the first compile in the next VM to compare with (see
      # Hologram.Compiler.CompileInputs). None while a page is pending: the next compile must run to
      # build it, whatever changed.
      maybe_record_compile_inputs(served_bundles_info, compile_inputs_dump_path, opts)

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

  # The files of the data model bundle the build serves, which the cleanup at the end keeps.
  defp data_model_bundle_artifacts(nil), do: []

  defp data_model_bundle_artifacts(data_model_bundle) do
    [
      data_model_bundle.static_bundle_path,
      Compiler.gzip_path(data_model_bundle.static_bundle_path)
    ]
  end

  # The pages graph is shared with the batches once, and only when a page is left to build: the
  # runtime and the chunks alone read no page's reach. A page listed before the batches has its
  # MFAs already, but the struct types it names are listed with its batch. So a compile with no
  # page to rebuild neither waits for the pages graph nor copies it.
  defp build_batches(remaining_pages, shared, bundles, context) do
    if MapSet.size(remaining_pages) == 0 do
      build_page_batches(remaining_pages, shared, bundles, context)
    else
      CallGraph.with_shared_graph(context.call_graph, fn read_graph ->
        build_page_batches(
          remaining_pages,
          shared,
          bundles,
          %{context | read_graph: read_graph}
        )
      end)
    end
  end

  # Returns the module info PLT of this compile, which is the cache's, the module digests diff,
  # whether any entry changed, and the entries a warm compile replaced or removed (none for a cold
  # one, which has nothing to go back to). A cold compile reads every module against the dump, diffs the two
  # PLTs, copies the result into the cache's PLT, once, and compares the two PLTs' entries. A warm
  # one brings the cache's PLT in line in place, reading the modules the compiler reported and the
  # beams whose mtime or size moved among the beams a save can rewrite, and takes the diff from that
  # scan (see Hologram.Compiler.patch_module_info_plt!/5). The cache holds the editable modules only
  # between two finished compiles, so nil means cold.
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
    {cache.module_info_plt, module_digests_diff, new_infos != PLT.get_all(old_plt), %{}}
  end

  defp build_module_info_plt(cache, _old_plt, dumped_at, editable_beams, compiled_modules, _sup) do
    {module_digests_diff, infos_changed?, previous_infos} =
      Compiler.patch_module_info_plt!(
        cache.module_info_plt,
        dumped_at,
        cache.editable_modules,
        editable_beams,
        compiled_modules
      )

    {cache.module_info_plt, module_digests_diff, infos_changed?, previous_infos}
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

  # Builds the pages still to rebuild in the batches the :next_batch option asks for, and with the
  # first one what every page shares - the runtime, the data model bundle and the chunks - given as
  # %{data_model?: true, entry_files_info: ...}, and returns the bundles the page digest PLT names
  # once the batches stop: the ones built, and for the pages the batches did not get to, the ones
  # they had. What every page shares is built even when the first answer is :stop, since the pages
  # kept and the pages built both load it.
  defp build_page_batches(remaining_pages, shared, bundles, context) do
    case next_batch(remaining_pages, context) do
      :stop ->
        bundle_batch([], shared, bundles, context)

      page_modules ->
        new_bundles = bundle_batch(page_modules, shared, bundles, context)
        new_remaining_pages = MapSet.difference(remaining_pages, MapSet.new(page_modules))

        build_page_batches(new_remaining_pages, @later_batch_shared, new_bundles, context)
    end
  end

  # The graph the pages are listed on: the runtime's copy without the runtime's MFAs, since every page
  # leaves out what the runtime bundle carries. None while there is no runtime copy (see
  # build_runtime_graph/3 and ensure_pages_graph/5).
  defp build_pages_graph(nil, _runtime_mfas), do: nil

  defp build_pages_graph(call_graph_for_runtime, runtime_mfas) do
    CallGraph.remove_runtime_mfas!(call_graph_for_runtime, runtime_mfas)
  end

  # Grows the graph to hold the chunks' code (see Hologram.Compiler.build_chunk_reach!/4) and returns
  # the chunks' entry vertices by type with the modules built. None on a compile that keeps the
  # chunk analysis: the graph holds the chunks' code since the compile that last changed it.
  defp build_chunk_reach(_call_graph, _ir_plt, _page_modules, _component_modules, true), do: nil

  defp build_chunk_reach(call_graph, ir_plt, page_modules, component_modules, false) do
    Compiler.build_chunk_reach!(call_graph, ir_plt, page_modules, component_modules)
  end

  # The copy of the graph the runtime's MFAs and the chunks' are listed on, and the data layer's
  # reach of every page it lists again or walks for the types it holds through rows, without the
  # manually ported MFAs. None when the runtime, the chunk analysis and the data layer are all kept
  # and no page is listed again: nothing reads it then.
  defp build_runtime_graph(_call_graph, true, _sup), do: nil

  defp build_runtime_graph(call_graph, false, sup) do
    call_graph
    |> CallGraph.clone(supervisor: sup)
    |> CallGraph.remove_manually_ported_mfas()
  end

  # Whether the chunk analysis a compile could keep by its graph is still good: the kept chunks were
  # grouped with these held types.
  defp chunk_analysis_kept?(false, _kept_chunks, _held_types), do: false

  defp chunk_analysis_kept?(true, kept_chunks, held_types) do
    kept_chunks.held_types == held_types
  end

  # The chunk reach and the runtime graph of a compile that found it must group the chunks again
  # after all. The runtime graph is copied again when the walk grew the graph, since the chunks are
  # listed on it, and a copy taken before the walk lacks what it built.
  defp ensure_chunk_reach(nil, runtime_graph, false, context) do
    chunk_reach =
      build_chunk_reach(
        context.call_graph,
        context.ir_plt,
        context.page_modules,
        context.component_modules,
        false
      )

    {chunk_reach, late_runtime_graph(runtime_graph, chunk_reach.built_modules, context)}
  end

  defp ensure_chunk_reach(chunk_reach, runtime_graph, _chunk_analysis_kept?, _context) do
    {chunk_reach, runtime_graph}
  end

  defp late_runtime_graph(runtime_graph, [], _context) when runtime_graph != nil do
    runtime_graph
  end

  defp late_runtime_graph(_runtime_graph, _built_modules, context) do
    build_runtime_graph(context.call_graph, false, context.supervisor)
  end

  # Whether the graph is still the one the last finished compile ended with, after the chunks' walk.
  defp graph_still_unchanged?(false, _chunk_reach), do: false

  defp graph_still_unchanged?(true, chunk_reach), do: chunk_built_modules(chunk_reach) == []

  # The struct types with an implementation of a client protocol: a fact of the graph, so a compile
  # that kept the chunk analysis finds it in the kept chunks.
  defp impl_types(kept_chunks, nil), do: kept_chunks.impl_types

  defp impl_types(_kept_chunks, chunk_reach) do
    Compiler.list_impl_types(chunk_reach.entries_by_type)
  end

  # The chunk bundles among the given built ones, by the signature each was built for: a chunk's
  # entry is named by its signature's digest.
  defp built_chunk_bundles_info(built_bundles_info, context) do
    signatures_by_digest =
      Map.new(context.chunk_entry_files_info, fn {signature, signature_digest, _entry_file_path} ->
        {signature_digest, signature}
      end)

    for %{bundle_name: "chunk", entry_name: signature_digest} = bundle_info <- built_bundles_info,
        into: %{} do
      {signatures_by_digest[signature_digest], bundle_info}
    end
  end

  # What the :bundles_built option is told of what every page shares: the runtime first, then the
  # data model bundle when the batch changed it, then the chunks.
  defp built_shared_entries(shared, data_model_changed?) do
    bundle_names =
      MapSet.new(shared.entry_files_info, fn {_entry_name, _entry_file_path, bundle_name} ->
        bundle_name
      end)

    for {entry, built?} <- [
          runtime: MapSet.member?(bundle_names, "runtime"),
          data_model: data_model_changed?,
          chunks: MapSet.member?(bundle_names, "chunk")
        ],
        built? do
      entry
    end
  end

  # Builds the given pages, and the runtime and the chunks when their entry files are given, and
  # records them: their states in the cache, the chunk registry PLT and the page digest PLT that
  # name them, and the pages no longer pending. The first batch writes or keeps the data model
  # bundle once esbuild is done (see write_data_model_bundle/2). The runtime and data model bundles
  # the batch replaces go once its dumps are written, since the asset path registry names them
  # until the :bundles_built option is told what was built (see built_shared_entries/2). A batch
  # with nothing to bundle tells it only of a data model bundle it changed, and of nothing when it
  # changed none.
  defp bundle_batch([], %{entry_files_info: []} = shared, bundles, context) do
    data_model_written? = write_data_model_bundle(shared, context)
    data_model_removed? = remove_replaced_data_model_bundles(shared, context)

    if data_model_written? or data_model_removed? do
      context.opts[:bundles_built].([:data_model])
    end

    bundles
  end

  defp bundle_batch(page_modules, shared, bundles, context) do
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
      Compiler.bundle(shared.entry_files_info ++ page_entry_files_info, context.opts)

    data_model_written? = write_data_model_bundle(shared, context)

    built_chunk_bundles_info = built_chunk_bundles_info(built_bundles_info, context)

    batch = %{
      chunk_types_by_page: list_batch_chunk_types(page_modules, context),
      mfas_by_page: Map.new(batch_mfas_by_page)
    }

    new_bundles =
      bundles
      |> put_built_bundles_info(built_bundles_info)
      |> put_built_chunk_bundles_info(built_chunk_bundles_info, context)
      |> Map.update!(:page_chunk_types, &Map.merge(&1, batch.chunk_types_by_page))

    dump_chunk_registry_plt(new_bundles, context)
    dump_page_digest_plt(new_bundles, context)

    remove_replaced_runtime_bundles(built_bundles_info, context.opts[:static_dir])

    # Recorded only now, so that a compile failing on anything above leaves nothing kept of this
    # batch: the next one builds it again, and removes what it replaces.
    keep_built_bundles(built_bundles_info, batch, context)
    keep_built_chunk_bundles(built_chunk_bundles_info, context)
    Cache.delete_pending_pages(page_modules)

    # After the state is kept, since no state brings this removal back: a retry runs it whatever is
    # kept, and the old bundle it then finds is what tells it to report the change.
    data_model_removed? = remove_replaced_data_model_bundles(shared, context)
    data_model_changed? = data_model_written? or data_model_removed?

    built_entries = built_shared_entries(shared, data_model_changed?) ++ page_modules
    context.opts[:bundles_built].(built_entries)

    new_bundles
  end

  # Builds the IR the given chunks' functions are rendered from.
  defp build_chunk_ir!(chunks, ir_plt, module_info_plt) do
    chunks
    |> chunk_mfas()
    |> Compiler.list_ir_modules(module_info_plt)
    |> then(&Compiler.build_missing_ir!(ir_plt, &1))
  end

  defp chunk_built_modules(nil), do: []
  defp chunk_built_modules(chunk_reach), do: chunk_reach.built_modules

  # Every chunk's MFAs.
  defp chunk_mfas(chunk_mfas_by_signature) do
    chunk_mfas_by_signature
    |> Map.values()
    |> Enum.concat()
  end

  defp compile_with_lock(opts) do
    lock_path = Path.join(opts[:build_dir], Reflection.compiler_lock_file_name())

    # The whole compile reads through a hold (see Hologram.Entity.Model.hold/0), not only its data
    # model step: it is what validates the code the hold is about, and a hold put during its later
    # steps doesn't stop those steps, which still read the model.
    with_lock(lock_path, "compiler", fn ->
      Model.compiling(fn -> compile(opts) end)
    end)
  end

  # The entry files of the given chunks (see Hologram.Compiler.create_chunk_entry_files/5), the IR
  # their functions read built first. None for no chunk.
  defp create_chunk_entry_files(chunks, _ir_plt, _encode_plt, _async_mfas, _opts)
       when chunks == %{},
       do: []

  defp create_chunk_entry_files(chunks, ir_plt, encode_plt, async_mfas, opts) do
    build_chunk_ir!(chunks, ir_plt, opts[:module_info_plt])
    Compiler.create_chunk_entry_files(chunks, ir_plt, encode_plt, async_mfas, opts)
  end

  # The call graph and the module infos are the before picture of the next VM's first compile (see
  # load_before_state/4). While both dumps on disk are the ones this VM wrote or loaded (the module
  # info dump's stamp is the given one), the graph dump describes this graph when the graph is
  # unchanged, and the module info dump these infos when the scan changed no entry; each is written
  # only when it would say something else. The graph changes only with the infos, so a graph dump is
  # never written without the module info dump. Another VM's dump written meanwhile (the stamp
  # moved), or a deleted graph dump, is written over. The first compile in a VM loaded both under
  # the compiler lock, so they are its own too; a build dir with no module info dump has none to
  # own, and one with a module info dump but no graph dump loaded neither, so both are written then.
  defp dump_before_picture(dump_stamp, call_graph, module_info_plt, opts) do
    own_dumps? = own_dumps?(dump_stamp, opts[:module_info_plt_dump_path])

    if not (opts[:graph_unchanged?] and own_dumps? and File.exists?(opts[:call_graph_dump_path])) do
      CallGraph.dump(call_graph, opts[:call_graph_dump_path])
    end

    if opts[:infos_changed?] or not own_dumps? do
      Compiler.dump_module_info_plt(module_info_plt, opts[:module_info_plt_dump_path])
    end
  end

  # The compile state is written when it moved since this VM last wrote or loaded it, and whenever
  # the dumps on disk are not the given stamp's: another VM's compile state may be there (see
  # own_dumps?/2).
  defp dump_compile_state(dump_stamp, compile_state_dump_path, module_info_plt_dump_path) do
    Cache.dump_compile_state(
      compile_state_dump_path,
      not own_dumps?(dump_stamp, module_info_plt_dump_path)
    )
  end

  # The chunk registry PLT is dumped with the page digest PLT (see dump_page_digest_plt/2): the
  # chunks each struct type needs, and the chunks each page a compile has built preloads, the ones
  # the types its client code names need, the ones the types the runtime's code names need and the
  # one with the implementations of the types synced rows can hold.
  defp dump_chunk_registry_plt(bundles, context) do
    {chunk_registry_plt, chunk_registry_plt_dump_path} =
      Compiler.build_chunk_registry_plt(
        bundles.chunks,
        bundles.page_chunk_types,
        Enum.concat(context.runtime_types, context.held_types),
        Keyword.put(context.opts, :supervisor, context.supervisor)
      )

    PLT.dump(chunk_registry_plt, chunk_registry_plt_dump_path)
    PLT.stop(chunk_registry_plt)
  end

  # Whether the dumps the data layer derivation writes are in the build dir.
  defp data_layer_dumps_exist?(opts) do
    dump_file_names = [
      Reflection.index_needs_plt_dump_file_name(),
      Reflection.page_types_plt_dump_file_name(),
      Reflection.queries_plt_dump_file_name()
    ]

    Enum.all?(dump_file_names, fn dump_file_name ->
      opts[:build_dir]
      |> Path.join(dump_file_name)
      |> File.exists?()
    end)
  end

  # The modules whose edit can move what the data layer read of a page: the ones reaching the edit,
  # and the protocols of the new implementations (see list_new_impls/4), since a page dispatching
  # one of those can enter the implementation, and no page's read holds it yet.
  defp data_layer_reaching_modules(reaching_modules, new_impls, module_info_plt) do
    new_impls
    |> MapSet.new(&CallGraph.implemented_protocol(&1, module_info_plt))
    |> MapSet.union(reaching_modules)
  end

  # The data layer is kept whole when the edit touches nothing it reads: no page's reach to list
  # again, no page gone, the data model and the derived definitions unchanged, the shapes of the
  # queries the code writes the ones it was derived with, and its dumps on disk from the compile
  # that derived it, which put the state only once they were written - so no other VM's compile
  # wrote the module info dump since this VM's last one (see own_dumps?/2): one that did derived
  # against other module infos, and its data layer dumps may be the ones there. A page is gone when
  # the kept reach holds a page the build no longer has. A component or a protocol implementation is
  # read through the pages reaching it, so an edit of one lists those pages again, or through the
  # walks of the types a page holds through rows, which an edit makes stale without listing the page
  # (see held_impls_changed?/4).
  defp data_layer_kept?(nil, _parts, _opts), do: false

  defp data_layer_kept?(kept_data_layer, parts, opts) do
    nothing_read_moved? =
      not Enum.any?([
        parts.pages_to_list != [],
        parts.data_model_changed?,
        parts.derived_stale?,
        parts.held_impls_changed?
      ])

    nothing_read_moved? and kept_data_layer[:query_shapes] == parts.query_shapes and
      map_size(parts.kept_page_reach) == map_size(kept_data_layer.pages) and
      parts.own_dumps? and data_layer_dumps_exist?(opts)
  end

  # What the data layer derives from the build, validated and dumped for the running app: the synced
  # types each page fills first, what the renderer and the sync layer read, and the statement the
  # data model bundle sets the client's data layer constants with, which is returned. What it was
  # derived from is kept with the statement (see Hologram.Compiler.Cache.put_data_layer/1). A
  # derivation that raises writes no dump and keeps nothing.
  #
  # A page's reach is listed again only when the edit can have moved it (see
  # partition_kept_page_reach/4); every other page keeps what the last derivation listed. It is
  # listed on the runtime's copy of the graph: without the manually ported MFAs, which is what the
  # bundles are derived from, and with the runtime's MFAs still in it (see build_pages_graph/2), so
  # that a component reached through a runtime MFA is still one the page can reach.
  #
  # The derived definitions are put where the build reads them before anything is derived, since the
  # types read what the derived fields they name are defined as. The table is the running app's in
  # a dev server's VM, so a derivation that raises puts the kept ones back, which the dumps it
  # leaves in place were derived with.
  defp derive_data_layer!(context) do
    derived = derived_definitions(context)
    Derived.put_definitions(derived.definitions)

    try do
      derive_data_layer_with!(context, derived)
    catch
      kind, reason ->
        restore_derived_definitions(context.kept_data_layer)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp derive_data_layer_with!(context, derived) do
    %{
      call_graph: call_graph,
      call_graph_for_runtime: call_graph_for_runtime,
      entity_types: entity_types,
      ir_plt: ir_plt,
      module_info_plt: module_info_plt,
      opts: opts,
      pages_to_list: pages_to_list
    } = context

    listed_reach =
      pages_to_list
      |> Compiler.list_reach_by_page(call_graph_for_runtime)
      |> Compiler.put_impl_mfas(call_graph_for_runtime)

    # Only the pages listed again: every other page keeps the reach the last derivation listed, and
    # passed this check then.
    Compiler.validate_server_only_mfas!(listed_reach)

    # Asked of the UNSPLIT graph on purpose: can?/3 is manually ported, so the graph the
    # bundles are derived from no longer holds the vertex to ask about - while the question is
    # exactly whether the bundles reach it.
    permission_checking_pages =
      pages_to_list
      |> Compiler.list_reach_by_page(call_graph)
      |> Compiler.pages_checking_permissions()
      |> Enum.concat(Compiler.pages_checking_permissions_in_impls(listed_reach, call_graph))

    base_reach_by_page =
      listed_reach
      |> Compiler.build_kept_page_reach(permission_checking_pages, module_info_plt, ir_plt)
      |> then(&Map.merge(context.kept_page_reach, &1))

    # Everything below counts the implementations of the types a page holds through rows. What's
    # kept is the reach from before that, so that one removed takes what it named with it.
    {reach_by_page, held_impl_walks} =
      Compiler.fold_held_impls(
        base_reach_by_page,
        context.kept_held_impl_walks,
        call_graph_for_runtime,
        call_graph,
        ir_plt
      )

    # Checked on every derivation, the kept pages' queries too: a model change can make one that
    # was valid refused.
    Compiler.validate_query_chains!(reach_by_page, module_info_plt)

    sync_constants =
      Compiler.build_sync_constants(reach_by_page, module_info_plt)

    # Derived from every page's reach rather than from the bundles, so the dumps are whole before
    # the first batch, whatever batch the batches stop at.
    {page_types_plt, page_types_plt_dump_path} =
      Compiler.build_page_types_plt(
        sync_constants.page_types,
        Keyword.put(opts, :supervisor, context.supervisor)
      )

    # The access needs of what the server runs, dumped so that a boot builds the indexes they need
    # without deriving anything. Selected here once, so that two indexes deriving one name fail the
    # build rather than the boot.
    mapping = Mapper.derive!(entity_types, Model.roles())

    query_shapes =
      context.query_shapes
      |> Map.values()
      |> Enum.concat()
      |> Enum.uniq()
      |> Enum.sort()

    index_needs = Compiler.build_index_needs(sync_constants.synced_types, query_shapes, mapping)

    IndexPlan.select(IndexPlan.framework_needs(mapping) ++ index_needs, mapping)

    {index_needs_plt, index_needs_plt_dump_path} =
      Compiler.build_index_needs_plt(
        index_needs,
        Keyword.put(opts, :supervisor, context.supervisor)
      )

    # What the renderer and the sync layer read at boot: the derived fields' definitions, the entity
    # types sync sends rows of, and whether a page checks permissions on the client - which makes
    # the rows carry the server's verdicts and syncs the rows the rules read.
    {queries_plt, queries_plt_dump_path} =
      Compiler.build_queries_plt(
        %{
          derived: derived.definitions,
          permission_checking?: Compiler.permission_checking?(reach_by_page),
          synced_types: sync_constants.synced_types
        },
        Keyword.put(opts, :supervisor, context.supervisor)
      )

    # The data model bundle sets the client's data layer constants, so it is built from what they
    # render to: the model they render reads what the entity types declare now, so the two are
    # built together (see Hologram.Compiler.build_sync_constants_js/1).
    sync_constants_js = Compiler.build_sync_constants_js(sync_constants)

    # Not narrowed to the types a session may read, unlike what the data layer folds: a deploy that
    # adds a read rule can hand an open tab rows of such a type, and code that never runs is harmless.
    row_types = Compiler.list_row_types(sync_constants.synced_types)

    # The dumps once everything above passed, so that a derivation that raises leaves the dumps of
    # the last one that did not, which the kept data layer state describes.
    dump_index_needs_plt(index_needs_plt, index_needs_plt_dump_path)
    dump_page_types_plt(page_types_plt, page_types_plt_dump_path)
    dump_queries_plt(queries_plt, queries_plt_dump_path)

    Cache.put_data_layer(%{
      derived: derived,
      held_impl_walks: held_impl_walks,
      impl_seeds: context.impl_seeds,
      pages: base_reach_by_page,
      query_shapes: context.query_shapes,
      row_types: row_types,
      sync_constants_js: sync_constants_js
    })

    %{js: sync_constants_js, row_types: row_types}
  end

  # The index needs PLT is dumped once, after the data layer is validated and before the batches,
  # like the page types PLT.
  defp dump_index_needs_plt(index_needs_plt, index_needs_plt_dump_path) do
    PLT.dump(index_needs_plt, index_needs_plt_dump_path)
  end

  # The page types PLT is dumped once, after the data layer is validated and before the batches:
  # the types are derived from every page's reach rather than from the bundles.
  defp dump_page_types_plt(page_types_plt, page_types_plt_dump_path) do
    PLT.dump(page_types_plt, page_types_plt_dump_path)
  end

  # The queries PLT is dumped once, after the data layer is validated and before the batches, like
  # the page types PLT.
  defp dump_queries_plt(queries_plt, queries_plt_dump_path) do
    PLT.dump(queries_plt, queries_plt_dump_path)
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
  # The chunks as bundled, by signature, with their sizes (see Hologram.Compiler.fold_chunks/5). A
  # compile that kept the chunk analysis has both in the kept state. One that lists the chunks
  # again folds them with the kept sizes it can reuse (see reusable_chunk_sizes/3), so that a
  # chunk whose functions and modules are untouched is not rendered again, nor its IR built or its
  # functions encoded in a new VM.
  defp fold_chunks(true, kept_chunks, _listed, _ir_plt, _encode_plt, _async_mfas, _opts) do
    %{chunks: kept_chunks.mfas_by_signature, sizes: kept_chunks.sizes}
  end

  defp fold_chunks(false, _kept_chunks, listed, ir_plt, encode_plt, async_mfas, opts) do
    Compiler.fold_chunks(listed, ir_plt, encode_plt, async_mfas, opts)
  end

  defp forget_removed_pages(pages_plt, page_modules) do
    pages_plt
    |> PLT.keys()
    |> Kernel.--(page_modules)
    |> Enum.each(&Cache.delete_page/1)
  end

  # Whether the module's source is in Hologram's lib dir, given with a trailing slash.
  defp hologram_lib_module?(module, hologram_lib_prefix) do
    module
    |> Reflection.source_path()
    |> String.starts_with?(hologram_lib_prefix)
  end

  # The bundle of each chunk the kept state names, served until the first batch replaces the ones
  # to rebuild. With no chunk to build no batch replaces any, so only the kept ones: a signature
  # the app no longer has goes with the cleanup. None without a state.
  defp initial_chunk_bundles_info(nil, _kept_chunk_bundles_info, _chunks_to_build), do: %{}

  defp initial_chunk_bundles_info(_kept_chunks, kept_chunk_bundles_info, chunks_to_build)
       when chunks_to_build == %{},
       do: kept_chunk_bundles_info

  defp initial_chunk_bundles_info(kept_chunks, _kept_chunk_bundles_info, _chunks_to_build) do
    kept_chunks.bundle_infos
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
  # does not reach: a state per page bundle it wrote, and the runtime's inputs with its bundle. The
  # chunk bundles are recorded together (see keep_built_chunk_bundles/2).
  defp keep_built_bundles(built_bundles_info, batch, context) do
    Enum.each(built_bundles_info, fn
      %{bundle_name: "chunk"} ->
        :ok

      %{bundle_name: "page", entry_name: page_module} = bundle_info ->
        mfas = batch.mfas_by_page[page_module]

        page_state = %{
          bundle_info: bundle_info,
          chunk_types: batch.chunk_types_by_page[page_module],
          modules: page_state_modules(mfas)
        }

        Cache.put_page(page_module, page_state, mfas)

      %{bundle_name: "runtime"} = bundle_info ->
        Cache.put_runtime(%{
          app_versions: context.app_versions,
          bundle_info: bundle_info,
          client_config: context.client_config,
          js_binding_modules: context.runtime_js_binding_modules,
          mfas: context.runtime_mfas,
          dynamic_calls: context.gate.runtime,
          subsystems: context.subsystems,
          types: context.runtime_types
        })
    end)
  end

  # Records the chunk bundles a batch built, next to the kept ones, with what they were built from.
  defp keep_built_chunk_bundles(built_chunk_bundles_info, _context)
       when built_chunk_bundles_info == %{},
       do: :ok

  defp keep_built_chunk_bundles(built_chunk_bundles_info, context) do
    put_chunk_state(
      Map.merge(context.kept_chunk_bundles_info, built_chunk_bundles_info),
      context.chunks,
      context.chunk_sizes,
      context.chunk_types
    )
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
      | chunks: nil,
        data_layer: nil,
        encoding_inputs: nil,
        js_input_paths: MapSet.new(),
        pending_pages: MapSet.new(),
        runtime: nil,
        template_modules: nil,
        template_refs: nil
    }
  end

  # The chunks kept with their bundles, each on its own: one whose kept bundle was built from the
  # same functions, none of whose modules was edited, whose files it read are unchanged (see
  # Hologram.Compiler.js_inputs_changed?/2) and whose bundle can be served from the static dir (see
  # Hologram.Compiler.usable_bundle?/2), unless the JS imports the runtime registers changed: a
  # chunk leaves those out, as a page does. Every struct type has a chunk, so an edit of a struct
  # module rebuilds the chunks that carry it and no other. None without a state.
  defp keep_chunk_bundles(nil, _chunks, _reaching_modules, _inputs), do: %{}

  defp keep_chunk_bundles(kept_chunks, chunks, reaching_modules, inputs) do
    if inputs[:js_bindings_changed?] do
      %{}
    else
      for {signature, mfas} <- chunks,
          bundle_info = kept_chunks.bundle_infos[signature],
          bundle_info != nil,
          kept_chunks.mfas_by_signature[signature] == mfas,
          modules = page_state_modules(mfas),
          MapSet.disjoint?(modules, reaching_modules),
          not Compiler.js_inputs_changed?(bundle_info.js_inputs, inputs[:js_fingerprints]),
          Compiler.usable_bundle?(bundle_info, inputs[:static_dir]),
          into: %{} do
        {signature, bundle_info}
      end
    end
  end

  # The kept chunk state is replaced before the batches by one that names the kept bundles alone: a
  # compile that fails while bundling leaves the next one keeping those and rebuilding the rest.
  # The batch that builds the rest records them next to the kept ones.
  defp keep_chunk_state(kept_chunk_bundles_info, chunks, chunk_sizes, chunk_types) do
    put_chunk_state(kept_chunk_bundles_info, chunks, chunk_sizes, chunk_types)
  end

  # The runtime bundle carries the functions every page leaves out, so it is rebuilt when its MFAs,
  # the JS imports it registers or the app versions it names differ from the kept ones, and when a
  # module of those MFAs was edited: its functions are in the bundle, so their code is too. It is
  # rebuilt too when a file its bundle read changed (see Hologram.Compiler.js_inputs_changed?/2),
  # and when the client config or the subsystems it ships differ from this compile's. The data
  # model is none of its inputs: it goes into a bundle of its own (see write_data_model_bundle/2),
  # so a data model edit leaves the runtime bundle as it is. Its bundle, gzip copy and source map
  # are all required, since nothing else in the compile would recreate a missing one.
  defp keep_runtime_bundle?(nil, _reaching_modules, _inputs), do: false

  defp keep_runtime_bundle?(kept_runtime, reaching_modules, inputs) do
    not Compiler.runtime_changed?(
      kept_runtime,
      inputs[:mfas],
      inputs[:js_binding_modules],
      inputs[:app_versions]
    ) and
      kept_runtime.client_config == inputs[:client_config] and
      kept_runtime.subsystems == inputs[:subsystems] and
      not Compiler.js_inputs_changed?(
        kept_runtime.bundle_info.js_inputs,
        inputs[:js_fingerprints]
      ) and
      runtime_modules_untouched?(inputs[:mfas], reaching_modules) and
      Compiler.usable_bundle?(kept_runtime.bundle_info, inputs[:static_dir])
  end

  # The kept runtime state describes the bundle this compile replaces. A compile that fails during
  # the bundling leaves the next one diffing against the infos kept after it, which show no edit, so
  # the state is forgotten when the runtime is rebuilt: without it the next compile rebuilds the
  # runtime. A kept bundle keeps its state, but what the runtime's dynamic calls open is taken again
  # whenever the graph changes (the page callers of the exposed runtime functions move with the
  # pages), and a later compile that keeps the runtime's MFAs reads it from the state.
  defp keep_runtime_state(kept_runtime, [], runtime_dynamic_calls) do
    if runtime_dynamic_calls != kept_runtime.dynamic_calls do
      Cache.put_runtime(%{kept_runtime | dynamic_calls: runtime_dynamic_calls})
    end
  end

  defp keep_runtime_state(_kept_runtime, _runtime_entry_files_info, _runtime_dynamic_calls) do
    Cache.put_runtime(nil)
  end

  # The first compile in a VM validated every templatable. A later one updates the kept entries with
  # the ones it validated, and drops the entries of modules that are no longer templatables (removed,
  # or edited into something else).
  defp keep_template_entries(nil, _templatable_modules, validated_entries) do
    validated_entries
  end

  defp keep_template_entries(kept_entries, templatable_modules, validated_entries) do
    kept_entries
    |> Map.take(templatable_modules)
    |> Map.merge(validated_entries)
  end

  # Each page's layout, as the module info PLT records it, or as the page names it when its info
  # doesn't, the way the call graph's walk looks it up (see
  # Hologram.Compiler.CallGraph.list_page_entry_mfas/2).
  defp page_layouts(page_modules, module_info_plt) do
    Map.new(page_modules, fn page_module ->
      layout_module =
        PLT.get!(module_info_plt, page_module).layout_module || page_module.__layout_module__()

      {page_module, layout_module}
    end)
  end

  # What every page's walk of the implementations starts with (see
  # Hologram.Compiler.CallGraph.page_impl_seeds/2). A walk of the graph, so a compile that left the
  # graph as it was finds the ones the kept data layer was derived with.
  defp impl_seeds(%{impl_seeds: impl_seeds}, _call_graph, true), do: impl_seeds

  defp impl_seeds(_kept_data_layer, call_graph, _graph_unchanged?) do
    CallGraph.page_impl_seeds(call_graph)
  end

  # Whether the walks of the implementations of the types pages hold through rows can have moved
  # though no page is listed again: a kept page's walk met the edit, or there is a new protocol
  # implementation (see list_new_impls/4), which a page holding its type can enter though nothing it
  # reaches was edited. One removed is among the modules of the walks that entered it.
  defp held_impls_changed?(%{held_impl_walks: walks}, kept_pages, kept_walks, new_impls) do
    new_impls != [] or Map.take(walks, kept_pages) != kept_walks
  end

  defp held_impls_changed?(_kept_data_layer, _kept_pages, _kept_walks, _new_impls), do: true

  # The protocol implementations this compile brought: the added modules that are one, and the
  # edited ones that implement another protocol than before or none did, since a walk dispatching
  # their protocol can't have entered them. `defimpl A.B, for: C` and `defimpl A, for: B.C` are one
  # module. What an edited module was is in the entries a warm compile replaced, or in the dump a
  # cold one diffed against.
  defp list_new_impls(module_digests_diff, module_info_plt, old_module_info_plt, previous_infos) do
    edited_to_new_protocol =
      Enum.filter(module_digests_diff.edited_modules, fn module ->
        previous_info =
          with :error <- Map.fetch(previous_infos, module) do
            PLT.get(old_module_info_plt, module)
          end

        info_protocol(previous_info) != info_protocol(PLT.get(module_info_plt, module))
      end)

    Enum.filter(
      module_digests_diff.added_modules ++ edited_to_new_protocol,
      &impl_info?(PLT.get(module_info_plt, &1))
    )
  end

  defp impl_info?({:ok, %{protocol_implementation?: true}}), do: true

  defp impl_info?(_module_info), do: false

  defp info_protocol({:ok, %{implemented_protocol: protocol}}), do: protocol

  defp info_protocol(_module_info), do: nil

  # The kept walks of the implementations of the types each kept page holds through rows (see
  # Hologram.Compiler.fold_held_impls/5), without the walks of a page one of whose walks reached or
  # named a module reaching the edit.
  defp keep_held_impl_walks(%{held_impl_walks: walks}, kept_page_reach, reaching_modules) do
    walks
    |> Map.take(Map.keys(kept_page_reach))
    |> Map.reject(fn {_page_module, walks_by_types} ->
      Enum.any?(walks_by_types, fn {_types, walk} ->
        not MapSet.disjoint?(walk.modules, reaching_modules)
      end)
    end)
  end

  defp keep_held_impl_walks(_kept_data_layer, _kept_page_reach, _reaching_modules), do: %{}

  # The page's kept reach when it still holds: the page has one, and neither the modules it names
  # nor the ones the implementations it can dispatch to reach meet the modules reaching the edit.
  defp keepable_page_reach(kept_data_layer, page_module, reaching_modules) do
    with {:ok, reach} <- Map.fetch(kept_data_layer.pages, page_module),
         true <- MapSet.disjoint?(reach.modules, reaching_modules),
         true <- MapSet.disjoint?(reach.impl_modules, reaching_modules) do
      {:ok, reach}
    else
      _fallback -> :error
    end
  end

  defp restore_derived_definitions(%{derived: derived}),
    do: Derived.put_definitions(derived.definitions)

  defp restore_derived_definitions(_kept_data_layer), do: :ok

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

  # The first run in a VM to get past the gates (see put_first_compile/1) has nothing to do when the
  # world is as the record of the last compile that built every page says (see
  # Hologram.Compiler.CompileInputs), and it can tell before it loads anything. A later run in the
  # same VM does not consult the record, whether it follows a compile or a run that found nothing
  # changed: the record can be another OS process's since, whose modules this VM still runs the old
  # code of until a compile unloads them (see unload_replaced_modules/3). The data layer's dumps
  # have to stand too: the record names the static files, not the dumps the boot reads, and a
  # missing one is written again only by a compile.
  defp nothing_changed?(opts) do
    if opts[:first_compile?] do
      record =
        opts[:build_dir]
        |> Path.join(Reflection.compile_inputs_dump_file_name())
        |> CompileInputs.load()

      record != nil and CompileInputs.unchanged?(record, opts) and data_layer_dumps_exist?(opts)
    else
      false
    end
  end

  # A page's old bundle stays until the cleanup at the end, and the runtime's until its batch is
  # done (see remove_replaced_runtime_bundles/2). The chunk bundles are put together (see
  # put_built_chunk_bundles_info/2).
  defp put_built_bundles_info(bundles, built_bundles_info) do
    Enum.reduce(built_bundles_info, bundles, fn
      %{bundle_name: "chunk"}, acc ->
        acc

      %{bundle_name: "page", entry_name: page_module} = bundle_info, acc ->
        %{acc | pages: Map.put(acc.pages, page_module, bundle_info)}

      %{bundle_name: "runtime"} = bundle_info, acc ->
        %{acc | runtime: bundle_info}
    end)
  end

  # The chunks built join the kept ones, and the rest of the old set goes: a signature the app no
  # longer has, and the bundles the built ones replace. An old chunk's bundle stays on disk until
  # the cleanup at the end.
  defp put_built_chunk_bundles_info(bundles, built_chunk_bundles_info, _context)
       when built_chunk_bundles_info == %{},
       do: bundles

  defp put_built_chunk_bundles_info(bundles, built_chunk_bundles_info, context) do
    %{bundles | chunks: Map.merge(context.kept_chunk_bundles_info, built_chunk_bundles_info)}
  end

  # Records the given chunk bundles with the chunks they were built from, the sizes those were
  # folded by, and the types they were grouped with.
  defp put_chunk_state(bundle_infos, chunks, chunk_sizes, chunk_types) do
    modules =
      chunks
      |> chunk_mfas()
      |> page_state_modules()

    Cache.put_chunks(%{
      bundle_infos: bundle_infos,
      held_types: chunk_types.held_types,
      impl_types: chunk_types.impl_types,
      mfas_by_signature: chunks,
      modules: modules,
      sizes: chunk_sizes
    })
  end

  # Replaces what the running app knows of the data model. The caches derived from the model cache
  # are dropped with it.
  defp put_model_facts(entity_types, role_modules, user_entity) do
    RoleGrant.reset_resolution_cache()
    Model.put_facts(entity_types, role_modules, user_entity)
    Policy.reset_model_facts_cache()
    Edges.reset_index_cache()
    Rules.reset_cache()
  end

  # The components of the build. Overridable so this project's own test suite can choose them.
  # Defaulted here rather than in build_default_opts/0 so a run that skips compilation does not pay
  # the sweep.
  defp list_component_modules(module_info_plt, opts) do
    opts[:component_modules] || Compiler.list_components(module_info_plt)
  end

  # The shapes of the queries server code writes, by module (see Hologram.Query.Shape): the ones the
  # kept data layer was derived with, the modules the edit added, edited or removed read again. A
  # module's shapes are in its debug info, so a module whose shapes changed is an edited one. Every
  # module's are read when nothing is kept, or what is kept was derived without them.
  defp list_query_shapes(%{query_shapes: kept_shapes}, module_info_plt, module_digests_diff)
       when is_map(kept_shapes) do
    %{
      added_modules: added_modules,
      edited_modules: edited_modules,
      removed_modules: removed_modules
    } = module_digests_diff

    kept_shapes
    |> Map.drop(edited_modules ++ removed_modules)
    |> Map.merge(Compiler.list_query_shapes(module_info_plt, added_modules ++ edited_modules))
  end

  defp list_query_shapes(_kept_data_layer, module_info_plt, _module_digests_diff) do
    Compiler.list_query_shapes(module_info_plt)
  end

  # The modules whose callers' asks are judged: every one when nothing was kept, and when the
  # vocabulary the asks are judged against can have moved (see data_model_changed?/2). Else the
  # added and edited modules alone: the rest were judged by the compile that derived the kept data
  # layer, and their IR need not be built again (see Hologram.Compiler.operation_asks/3).
  defp operation_ask_modules(nil, _module_digests_diff, _data_model_changed?), do: nil

  defp operation_ask_modules(_kept_data_layer, _module_digests_diff, true), do: nil

  defp operation_ask_modules(_kept_data_layer, module_digests_diff, false) do
    module_digests_diff.added_modules ++ module_digests_diff.edited_modules
  end

  # Whether the vocabulary the queries and the operation asks are judged against can have moved: an
  # edited, added or removed entity, role or policy module moves it. A removed module's kind cannot
  # be read any more, so a removal counts. An added or edited module's kind is read from the module
  # info PLT, which holds this compile's entry for it.
  defp data_model_changed?(module_digests_diff, module_info_plt) do
    %{added_modules: added, edited_modules: edited, removed_modules: removed} =
      module_digests_diff

    removed != [] or Enum.any?(added ++ edited, &data_model_module?(&1, module_info_plt))
  end

  defp data_model_module?(module, module_info_plt) do
    Reflection.entity?(module, module_info_plt) or Reflection.role?(module, module_info_plt) or
      Reflection.policy?(module, module_info_plt)
  end

  # The derived definitions the data layer reads: the kept ones while nothing they were resolved
  # from moved, else resolved again.
  defp derived_definitions(%{derived_stale?: false, kept_data_layer: %{derived: derived}}),
    do: derived

  # Resolved definitions are checked against the declarations of every type they reach, which only a
  # resolved definition names - kept ones passed that check when they were resolved.
  defp derived_definitions(context) do
    derived = Compiler.resolve_derived_definitions(context.entity_types, context.ir_plt)

    DerivedValidator.validate_model!(context.entity_types, derived.definitions)

    derived
  end

  # Whether the kept derived definitions can be out of date: none kept, a data model change - the
  # declarations they read and every derived field's function live in entity types - or an edit or
  # removal of a module a walk followed calls into when they were resolved.
  defp derived_stale?(nil, _module_digests_diff, _data_model_changed?), do: true

  defp derived_stale?(_kept_data_layer, _module_digests_diff, true), do: true

  defp derived_stale?(kept_data_layer, module_digests_diff, false) do
    case kept_data_layer do
      %{derived: %{read_modules: read_modules}} ->
        changed_modules =
          module_digests_diff.edited_modules ++ module_digests_diff.removed_modules

        Enum.any?(read_modules, &(&1 in changed_modules))

      # A data layer state from before derived fields holds none.
      _kept_without_derived ->
        true
    end
  end

  # The data layer's statement for the data model bundle: the kept data layer's when it is kept (see
  # data_layer_kept?/3), else the one derived now (see derive_data_layer!/1).
  defp data_layer_output(true, %{kept_data_layer: kept_data_layer}) do
    %{js: kept_data_layer.sync_constants_js, row_types: kept_data_layer.row_types}
  end

  defp data_layer_output(false, context), do: derive_data_layer!(context)

  # Marks that a compile started in this VM, a run that finds nothing changed included, and puts in
  # the opts whether it is the VM's first (see nothing_changed?/1 and unload_replaced_modules/3).
  defp put_first_compile(opts) do
    Keyword.put(opts, :first_compile?, not Cache.mark_compile_started())
  end

  # Whether the module info dump on disk is the one the given stamp belongs to (see
  # Hologram.Compiler.module_info_dump_stamp/1): the one this VM wrote last, or the one the first
  # compile in a VM loaded, under the compiler lock, so that nothing wrote it since. A dump another
  # VM wrote within the same second has another token. No dump and no stamp count as the same.
  defp own_dumps?(dump_stamp, module_info_plt_dump_path) do
    Compiler.module_info_dump_stamp(module_info_plt_dump_path) == dump_stamp
  end

  defp page_state_modules(mfas) do
    mfas
    |> Enum.map(fn {module, _function, _arity} -> module end)
    |> MapSet.new()
  end

  # Splits the pages into the ones whose kept reach still holds, keyed by page, and the ones whose
  # reach the data layer lists again: a page with no kept reach (a new page, or nothing kept), and a
  # page whose kept modules meet the given modules, for the reason a page's bundle is rebuilt then
  # (see Hologram.Compiler.partition_affected_pages/6). Every page is listed again when what the
  # walks of the implementations start with moved, since it's the same for every page. A page no
  # longer in the build is left out of both.
  defp partition_kept_page_reach(nil, page_modules, _impl_seeds, _reaching_modules),
    do: {%{}, page_modules}

  defp partition_kept_page_reach(
         %{impl_seeds: impl_seeds} = kept_data_layer,
         page_modules,
         impl_seeds,
         reaching_modules
       ) do
    {kept_page_reach, pages_to_list} =
      Enum.reduce(page_modules, {%{}, []}, fn page_module, {kept, to_list} ->
        case keepable_page_reach(kept_data_layer, page_module, reaching_modules) do
          {:ok, reach} -> {Map.put(kept, page_module, reach), to_list}
          :error -> {kept, [page_module | to_list]}
        end
      end)

    {kept_page_reach, Enum.reverse(pages_to_list)}
  end

  defp partition_kept_page_reach(_kept_data_layer, page_modules, _impl_seeds, _reaching_modules),
    do: {%{}, page_modules}

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

  # The kept chunk sizes a compile can fold with again: a size holds while the chunk's functions are
  # the ones it was sized with, which the key says, and their JavaScript is what it was, which the
  # encoding inputs say for every module and an edit denies for the edited ones and the ones that
  # reach them. None without a state.
  defp reusable_chunk_sizes(nil, _reaching_modules, _encoding_inputs_kept?), do: %{}
  defp reusable_chunk_sizes(_kept_chunks, _reaching_modules, false), do: %{}

  defp reusable_chunk_sizes(kept_chunks, reaching_modules, true) do
    Map.filter(kept_chunks.sizes, fn {mfas, _size} ->
      MapSet.disjoint?(page_state_modules(mfas), reaching_modules)
    end)
  end

  # The runtime's MFAs and the struct types its code names are a walk of the graph, so a compile
  # that kept them (see runtime_kept?/3) finds the ones the runtime bundle on disk was built from.
  defp runtime_analysis(kept_runtime, _call_graph, true) do
    %{mfas: kept_runtime.mfas, types: kept_runtime.types}
  end

  defp runtime_analysis(_kept_runtime, call_graph, false) do
    CallGraph.runtime_analysis(call_graph)
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

  # The optional runtime subsystems this build needs (see
  # Hologram.Compiler.optional_runtime_subsystems/0), one predicate per subsystem: the data layer
  # when the application declares an entity type, the same fact that gates the database children,
  # the sync handshake and the sync constants statement, and decides whether the build serves a
  # data model bundle (see Hologram.Compiler.data_model_bundle/3).
  defp runtime_subsystems([]), do: []

  defp runtime_subsystems(_entity_types), do: [:data_layer]

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

  # The struct types each of the batch's pages names in its client code (see
  # Hologram.Compiler.CallGraph.list_page_chunk_types/4), which decide the chunks the page preloads.
  # Listed on the graph the pages' MFAs are, with the same analyses.
  defp list_batch_chunk_types([], _context), do: %{}

  defp list_batch_chunk_types(page_modules, context) do
    # The tasks get the reader and the PLTs, not the context, which each would copy.
    %{analyses: analyses, module_info_plt: module_info_plt, read_graph: read_graph} = context

    page_modules
    |> TaskUtils.map_concurrently(fn page_module ->
      chunk_types =
        CallGraph.list_page_chunk_types(read_graph.(), page_module, analyses, module_info_plt)

      {page_module, chunk_types}
    end)
    |> Map.new()
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

  # The MFAs of each chunk by its signature (see Hologram.Compiler.group_mfas_by_signature/1): each
  # chunked type's MFAs without the runtime's, regrouped. A compile that did not grow the graph for
  # the chunks (see build_chunk_reach/5) finds the ones the chunk bundles on disk were built from,
  # as folded.
  defp list_chunk_mfas_by_signature(kept_chunks, nil, _graph, _runtime_mfas, _held_types) do
    kept_chunks.mfas_by_signature
  end

  defp list_chunk_mfas_by_signature(
         _kept_chunks,
         chunk_reach,
         call_graph_for_runtime,
         runtime_mfas,
         held_types
       ) do
    call_graph_for_runtime
    |> CallGraph.list_chunk_mfas_by_type(
      chunk_reach.entries_by_type,
      chunk_reach.client_protocols,
      runtime_mfas
    )
    |> Compiler.group_mfas_by_signature()
    |> Compiler.merge_held_chunks(held_types)
  end

  # What the runtime's dynamic calls open is taken from the runtime's MFAs, so a compile that kept
  # them (see runtime_kept?/3) keeps it too.
  defp list_runtime_dynamic_calls(kept_runtime, _call_graph, _runtime_mfas, _ir_plt, true),
    do: kept_runtime.dynamic_calls

  defp list_runtime_dynamic_calls(_kept_runtime, call_graph, runtime_mfas, ir_plt, false) do
    CallGraph.runtime_dynamic_calls(call_graph, runtime_mfas, ir_plt)
  end

  # The modules unload_replaced_modules/3 checks, with the status that makes a module stale: the
  # diff's added and edited modules if their code is not their beam's, and its removed ones if they
  # have no beam. When a cold compile took the diff against a module info dump this VM has not seen,
  # which may be another OS process's that matches its new beams, the loaded modules of every
  # editable app too: the editable beams', and the ones loaded from an editable app's ebin dir.
  defp list_unload_candidates(module_digests_diff, context) do
    diff_statuses =
      (module_digests_diff.added_modules ++ module_digests_diff.edited_modules)
      |> Map.new(&{&1, :modified})
      |> Map.merge(Map.new(module_digests_diff.removed_modules, &{&1, :removed}))

    if context.cache.editable_modules == nil and
         context.before_dump_stamp != context.cache.seen_dump_stamp do
      list_loaded_editable_modules()
      |> Map.new(&{&1, :removed})
      |> Map.merge(Map.new(context.editable_modules, &{&1, :modified}))
      |> Map.merge(diff_statuses)
    else
      diff_statuses
    end
  end

  # The loaded modules whose beam the VM names is in an editable app's ebin dir (see
  # Hologram.Reflection.list_editable_apps/0), the ones whose beam is gone included.
  defp list_loaded_editable_modules do
    ebin_dirs =
      for app <- Reflection.list_editable_apps(),
          lib_dir = :code.lib_dir(app),
          is_list(lib_dir),
          into: MapSet.new(),
          do: Path.expand("ebin", lib_dir)

    for {module, beam_path} <- :code.all_loaded(),
        is_list(beam_path),
        MapSet.member?(ebin_dirs, beam_dir(beam_path)),
        do: module
  end

  # Returns the cache, the module info PLT to diff against (the cache's own on a warm compile, which
  # the scan brings in line in place) and the stamp of the module info dump the before picture came
  # from (see Hologram.Compiler.module_info_dump_stamp/1), whose mtime is the dump time the module
  # info reuse guard takes. The kept module infos are the proof that the kept IR PLT and call graph
  # are exactly in line with them, whatever another VM wrote to the build dir since, and they are
  # trusted only between two finished compiles (the cache keeps the editable modules then). Without
  # them (the first compile in a VM, or after a failed one) the cache is emptied and the build dir
  # is the before picture: the graph comes from its dump and the module info dump written next to it
  # says what changed. The compile state dump next to them is the after picture, what the bundles on
  # disk were built from.
  defp load_before_state(build_dir, call_graph_dump_path, compile_state_dump_path, sup) do
    case Cache.get() do
      %{editable_modules: nil} ->
        :ok = Cache.reset_kept_state()
        cache = Cache.get()

        # The two dumps are one before picture, and the graph dump is never written without the
        # module info dump, so a module info dump without a graph dump is not a before picture:
        # diffing against it would report no changes and leave the empty graph with nothing to
        # patch. Neither is a graph dump of another dump version, which the graph does not load (see
        # CallGraph.load/2). Without a graph dump every module counts as added, of which the pages
        # and the broadcast callers are patched in, and the graph is grown from them (see
        # Hologram.Compiler.build_reach!/3).
        {module_info_plt, dump_stamp} =
          with true <- File.exists?(call_graph_dump_path),
               :ok <- CallGraph.load(cache.call_graph, call_graph_dump_path) do
            # The after picture of the compile that wrote the before picture: the bundles it left and
            # what they were built from. Its page states are trusted only against the diff of these
            # module infos, which is why it is loaded here and not with a module info dump alone. A
            # dump of another version, or none, leaves every page to be built.
            maybe_load_compile_state(compile_state_dump_path)

            {plt, dump_path, _dumped_at} =
              Compiler.maybe_load_module_info_plt(build_dir, supervisor: sup)

            {plt, Compiler.module_info_dump_stamp(dump_path)}
          else
            _no_usable_dump -> {PLT.start(supervisor: sup), nil}
          end

        # Taken after the loads, so that the snapshot holds what was loaded.
        {Cache.get(), module_info_plt, dump_stamp}

      cache ->
        # Cleared before anything is patched in place: a compile that dies mid-patch can leave the
        # kept graph without edges that only its callers would rebuild, and the kept infos half
        # scanned, so the next compile must start from the dumps rather than from a half-patched
        # graph. The infos are marked as kept again last, after the dumps.
        :ok = Cache.clear_module_infos()

        {cache, cache.module_info_plt, cache.dumped_at && {cache.dumped_at, cache.dump_token}}
    end
  end

  # The data model as this compile's module info PLT records it: no beam is read. The model cache
  # is filled before the validation, since the validators read it (the role grant store answers its
  # relationships from it). The :data_model_ready option is called once the model is valid.
  #
  # Nothing but the module info PLT has moved when this runs: the IR and the call graph are patched
  # after it. So a failure here, of any kind, is undone. The entries the update replaced are put
  # back, and the tracer still holds the compiled modules, so the next compile in this VM finds the
  # same changes again, from the kept state and not from the dumps. The model cache keeps what
  # this compile put there: it describes the modules that are loaded, valid or not. Live reload
  # keeps the model under a hold from a save until the runtime has loaded what a compile derived
  # from it, so meanwhile nothing but the compile reads it (see Hologram.Entity.Model.hold/0). The
  # failure is then told to the :data_model_failed option, with the kept state already back, and
  # raised again.
  defp load_data_model!(module_info_plt, before, opts) do
    entity_types = Reflection.list_entities(module_info_plt)
    role_modules = Reflection.list_roles(module_info_plt)
    user_entity = Reflection.user_entity(module_info_plt)

    put_model_facts(entity_types, role_modules, user_entity)
    validate_data_model!(entity_types, role_modules)
    opts[:data_model_ready].(entity_types, role_modules)

    :ok
  catch
    kind, reason ->
      stacktrace = __STACKTRACE__

      restore_before_state(module_info_plt, before)
      opts[:data_model_failed].(kind, reason)

      :erlang.raise(kind, reason, stacktrace)
  end

  # A dump of another version is not loaded (see Hologram.Compiler.Cache.load_compile_state/1): the
  # state stays empty, as it does with no dump.
  defp maybe_load_compile_state(compile_state_dump_path) do
    if File.exists?(compile_state_dump_path) do
      Cache.load_compile_state(compile_state_dump_path)
    end
  end

  # The JavaScript inputs are the served bundles' own records, so that a file saved while the compile
  # ran is recorded as the bundle that read it saw it.
  defp maybe_record_compile_inputs(served_bundles_info, dump_path, opts) do
    if MapSet.size(Cache.get().pending_pages) == 0 do
      js_inputs =
        served_bundles_info
        |> Enum.flat_map(& &1.js_inputs)
        |> Enum.uniq()

      opts
      |> CompileInputs.build()
      |> Map.put(:js_inputs, js_inputs)
      |> CompileInputs.dump(dump_path)
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

  # A check spells the entity operation it asks about, and a name no allow line on any entity type
  # declares is a typo or a rename - refused here rather than answered no forever. Judged on every
  # compile whose diff is not empty, whether or not the data layer is kept: an edit of a module no
  # page uses can add an ask. And on every compile that keeps no data layer, since no compile judged
  # the asks for it. Asked of the UNSPLIT graph: the ask functions are hand-ported, so the runtime
  # graph no longer holds the vertices whose callers this reads.
  defp maybe_validate_operations!(entity_types, call_graph, ir_plt, inputs) do
    %{
      data_model_changed?: data_model_changed?,
      kept_data_layer: kept_data_layer,
      module_digests_diff: module_digests_diff
    } = inputs

    if kept_data_layer == nil or
         module_digests_diff != %{added_modules: [], edited_modules: [], removed_modules: []} do
      Compiler.validate_operations!(entity_types, call_graph, ir_plt,
        modules: operation_ask_modules(kept_data_layer, module_digests_diff, data_model_changed?)
      )
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

  # The data model bundles the first batch replaces, or every one for a build that serves none.
  # Returns whether it removed any. A compile that failed after writing the new bundle left the old
  # one here, so the retry finds it, and still reports the change to the tabs.
  defp remove_replaced_data_model_bundles(%{data_model?: false}, _context), do: false

  defp remove_replaced_data_model_bundles(%{data_model?: true}, context) do
    kept_bundle_path = context.data_model_bundle && context.data_model_bundle.static_bundle_path

    Compiler.remove_data_model_bundles(context.opts[:static_dir], kept_bundle_path)
  end

  # The runtime bundle is found by scanning the static dir rather than through the page digest PLT,
  # so the ones a built runtime replaces go before the registry reloads, which could otherwise pick
  # one over it. Found by name rather than through the kept state, which a compile that failed after
  # bundling has forgotten while the old runtime is still on disk.
  defp remove_replaced_runtime_bundles(built_bundles_info, static_dir) do
    case Enum.find(built_bundles_info, &(&1.bundle_name == "runtime")) do
      nil ->
        :ok

      bundle_info ->
        kept_paths = [
          bundle_info.static_bundle_path,
          Compiler.gzip_path(bundle_info.static_bundle_path),
          bundle_info.static_source_map_path
        ]

        static_dir
        |> File.ls!()
        |> Enum.filter(&String.starts_with?(&1, "runtime-"))
        |> Enum.map(&Path.join(static_dir, &1))
        |> Enum.reject(&(&1 in kept_paths))
        |> Enum.each(&File.rm/1)
    end
  end

  defp remove_lock_file_with_invalid_os_pid(lock_path) do
    Logger.info("Hologram: removing lock file with invalid OS-level PID format")
    File.rm(lock_path)
  end

  # Known, unclosed race, shared with maybe_remove_abandoned_empty_lock/1 and widest
  # here: the removal is by path, not owner-verified. Deciding that os_pid is dead
  # takes milliseconds (SystemUtils.os_process_alive?/1 shells out to ps or tasklist),
  # and by the time File.rm/1 runs, the file at this path may no longer be the one
  # that was diagnosed. Two invocations in different OS processes reading the same lock
  # left behind by a killed process both diagnose it dead (two in one VM can't, since
  # they take the stale check in turns, see with_lock/3); the first removes it, acquires
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
  # needs a lock orphaned by a killed process, which the cleanup in with_file_lock/3
  # prevents on every normal exit, plus two invocations landing in the liveness check
  # within the same few milliseconds.
  defp remove_lock_for_dead_process(lock_path, os_pid) do
    Logger.info(
      "Hologram: removing stale lock file (OS-level process #{os_pid} no longer exists)"
    )

    File.rm(lock_path)
  end

  # Can't race an acquire in this VM, since the VM lock orders them (see with_lock/3), and another
  # OS process never removes a lock naming a live process. Two containers that share the build dir
  # and whose VMs got the same OS-level PID would take each other's live locks for their own, which
  # isn't supported: the liveness check can't see into another container's processes anyway.
  defp remove_lock_of_this_vm(lock_path) do
    Logger.info("Hologram: removing stale lock file (no process of this VM holds it)")
    File.rm(lock_path)
  end

  defp remove_unreadable_lock_file(lock_path) do
    Logger.info("Hologram: removing unreadable lock file")
    File.rm(lock_path)
  end

  # A cold compile kept nothing to go back to (its editable modules are nil): the next compile
  # starts from the dumps, as it would have.
  defp restore_before_state(_module_info_plt, %{editable_modules: nil}), do: :ok

  defp restore_before_state(module_info_plt, before) do
    Compiler.restore_module_infos(module_info_plt, before.previous_infos)
    Cache.put_module_infos(before.dump_stamp, before.editable_modules)
  end

  # Keeps the stamp of the module info dump as the one this VM saw in line with the beams, on a run
  # that found nothing changed (see list_unload_candidates/2).
  defp see_module_info_dump(opts) do
    opts[:build_dir]
    |> Path.join(Reflection.module_info_plt_dump_file_name())
    |> Compiler.module_info_dump_stamp()
    |> Cache.put_seen_dump_stamp()
  end

  defp stamp_mtime(nil), do: nil

  defp stamp_mtime({mtime, _token}), do: mtime

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

  # Unloads the loaded modules of the diff, and of every editable app after another process's module
  # info dump (see list_unload_candidates/2), whose code is not their beam's, or that have no beam
  # any more. Another OS process compiled or deleted them, so the VM still runs their old code, which
  # the server renders with and this compile reads props and routes from. Phoenix's reloader unloads
  # such modules too, but misses some: without its Mix listener it goes by the manifest's mtime in
  # whole seconds, and it covers only its reloadable apps. Unloaded the same way, so that a call
  # loads the new beam. The modules this VM's compiler reported are its own compile's, loaded new.
  # Hologram's own modules are left loaded: this compile runs them, and would run two versions of the
  # compiler at once. Nothing is unloaded on the first compile in a VM: the tracer reports none of
  # the modules Elixir compiled before it, which the VM loaded from the beams Elixir just wrote.
  defp unload_replaced_modules(_module_digests_diff, _compiled_modules, %{first_compile?: true}),
    do: :ok

  defp unload_replaced_modules(module_digests_diff, compiled_modules, context) do
    stale_statuses = list_unload_candidates(module_digests_diff, context)

    hologram_lib_prefix =
      Compiler
      |> Reflection.source_path()
      |> Path.dirname()
      |> Path.dirname()
      |> Kernel.<>("/")

    # In this order, since the source path is read from a loaded module, and the status costs an
    # md5 of the beam.
    stale_statuses
    |> Map.keys()
    |> Enum.filter(fn module ->
      not MapSet.member?(compiled_modules, module) and :code.is_loaded(module) != false and
        not hologram_lib_module?(module, hologram_lib_prefix)
    end)
    |> :code.module_status()
    |> Enum.each(fn {module, status} ->
      if status == stale_statuses[module] do
        :code.purge(module)
        :code.delete(module)
      end
    end)
  end

  # Writes the data model bundle of the build, or keeps it when it is on disk, and returns whether it
  # wrote it. Only in the first batch, and once esbuild is done. The bundle it replaces stays until
  # the batch is done (see remove_replaced_data_model_bundles/2), since the asset path registry
  # names it until then.
  defp write_data_model_bundle(%{data_model?: true}, %{data_model_bundle: bundle})
       when bundle != nil do
    Compiler.write_data_model_bundle!(bundle)
  end

  defp write_data_model_bundle(_shared, _context), do: false

  defp validate_data_model!(entity_types, role_modules) do
    EntityValidator.validate_model!(entity_types)
    PolicyValidator.validate_model!(entity_types, role_modules)

    # The mapping and the plan are discarded - only the fail-fast derivation checks matter here, the
    # plan's that no two of the indexes the framework's lookups need derive one name.
    entity_types
    |> Mapper.derive!(role_modules)
    |> IndexPlan.framework_plan()

    :ok
  end

  # Listed from the beams: no compile runs, so no module info PLT is in line with them. Listed and
  # validated only when an application's compile manifest moved since the record of the last
  # validation that passed (see Hologram.Compiler.DataModelInputs): a manifest moves whenever a
  # module of its application is compiled or removed, so a model that was valid against the same
  # manifests still is. A validation that fails raises before the record is written, so the next
  # invocation validates again.
  defp validate_uncompiled_data_model!(opts) do
    record_path = Path.join(opts[:build_dir], Reflection.data_model_inputs_dump_file_name())
    record = DataModelInputs.load(record_path)

    if record == nil or not DataModelInputs.unchanged?(record, opts) do
      entity_types = Reflection.list_entities()
      role_modules = Reflection.list_roles()
      user_entity = Enum.find(entity_types, &Reflection.user_entity?/1)

      put_model_facts(entity_types, role_modules, user_entity)
      validate_data_model!(entity_types, role_modules)

      # An invocation that never compiles may be the first thing to run in a fresh build.
      File.mkdir_p!(opts[:build_dir])

      opts
      |> DataModelInputs.build()
      |> DataModelInputs.dump(record_path)
    end

    :ok
  end

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

  # An empty lock file is a lock in the middle of being acquired, not an invalid one:
  # with_file_lock/3 creates the file with File.open/2 and only then writes the owner's PID
  # into it, so an invocation in another OS process can read it in between and must leave
  # it alone (one in this VM can't, see with_lock/3).
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

  # A lock naming this VM's OS-level PID is held by no process of this VM, since each holder in it
  # holds the VM lock as well, and so does the caller (see with_lock/3). Its holder was killed,
  # which skips the removal in with_file_lock/3, or an earlier VM with the same OS-level PID left
  # it, as after a container restart. The OS-level liveness check would always find this VM alive.
  defp validate_lock_file_and_proceed_accordingly(lock_path, os_pid_str) do
    case Integer.parse(os_pid_str) do
      {os_pid, _remainder} ->
        cond do
          Integer.to_string(os_pid) == System.pid() ->
            remove_lock_of_this_vm(lock_path)

          not SystemUtils.os_process_alive?(os_pid) ->
            remove_lock_for_dead_process(lock_path, os_pid)

          true ->
            :ok
        end

      :error ->
        remove_lock_file_with_invalid_os_pid(lock_path)
    end
  end

  # Runs here rather than in each module's own compilation: every module is compiled by now, so a
  # used component's __props__/0 is simply callable, with no compile-time dependency on it and no
  # deadlock when a component renders itself. Only the templates an edit can affect are validated
  # (see Hologram.Compiler.list_templatables_to_validate/3), and the IR of the ones no page reaches is
  # built for that alone. Returns the modules each templatable's template uses and the refs it
  # declares, kept for the next compile, and the refs each page renders, for its bundle.
  #
  # A template's refs depend on its own IR alone, so the ones it validates are summarized again and
  # the others kept. Whether they clash depends on every template a page renders, so the check runs
  # over all of them every compile, which reads no IR. A compile that kept no refs, after a compile
  # state written before they were kept, validates every template.
  defp validate_templates(
         templatable_modules,
         page_modules,
         module_digests_diff,
         cache,
         ir_plt,
         module_info_plt
       ) do
    kept_template_modules = if cache.template_refs, do: cache.template_modules

    modules_to_validate =
      Compiler.list_templatables_to_validate(
        templatable_modules,
        module_digests_diff,
        kept_template_modules
      )

    Compiler.build_missing_ir!(ir_plt, modules_to_validate)
    validated_template_modules = Compiler.validate_prop_usages(modules_to_validate, ir_plt)

    template_refs =
      keep_template_entries(
        kept_template_modules && cache.template_refs,
        templatable_modules,
        Compiler.list_template_refs_by_module(modules_to_validate, ir_plt)
      )

    ref_names_by_page =
      Compiler.check_template_refs(template_refs, page_layouts(page_modules, module_info_plt))

    template_modules =
      keep_template_entries(
        kept_template_modules,
        templatable_modules,
        validated_template_modules
      )

    {template_modules, template_refs, ref_names_by_page}
  end

  # Retries within itself, not with_lock/3: the VM lock is granted to its holder again, and the
  # inner release would free the outer one.
  defp with_file_lock(lock_path, lock_name, fun) do
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
        Logger.info("Hologram: #{lock_name} already running, waiting...")
        :timer.sleep(1_000)
        with_file_lock(lock_path, lock_name, fun)

      {:error, reason} ->
        raise "Hologram: failed to acquire #{lock_name} lock: #{inspect(reason)}"
    end
  end

  # Runs the given function while it holds the lock at the given path, which the given name names in
  # the log line of a wait and in the error of a failed acquire.
  #
  # The lock file keeps out compiles in other OS processes. Within this VM a VM lock keeps them out,
  # a :global lock on this node alone, taken before the file is touched and held until it is
  # removed, so a process reading the file holds it too, and a lock file naming this VM's OS-level
  # PID is then known to be stale (see validate_lock_file_and_proceed_accordingly/2). It is released
  # when its holder dies, killed included, which the file isn't. Keyed by the name, not the path, so
  # that two spellings of one path can't get two VM locks. Released on node() read again, since
  # distribution may have started or stopped meanwhile, which would make a release on the old node
  # name a no-op. Not re-entrant: the function must not take the same lock again.
  defp with_lock(lock_path, lock_name, fun) do
    vm_lock_id = {{__MODULE__, lock_name}, self()}

    if :global.set_lock(vm_lock_id, [node()], 0) do
      try do
        with_file_lock(lock_path, lock_name, fun)
      after
        :global.del_lock(vm_lock_id, [node()])
      end
    else
      Logger.info("Hologram: #{lock_name} already running, waiting...")
      :timer.sleep(1_000)
      with_lock(lock_path, lock_name, fun)
    end
  end
end
