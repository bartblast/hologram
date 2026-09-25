defmodule Hologram.Compiler do
  @moduledoc false

  alias Hologram.Commons.CryptographicUtils
  alias Hologram.Commons.FileUtils
  alias Hologram.Commons.PathUtils
  alias Hologram.Commons.PLT
  alias Hologram.Commons.StringUtils
  alias Hologram.Commons.SystemUtils
  alias Hologram.Commons.TaskUtils
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Digraph
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR
  alias Hologram.Reflection

  @type js_input_fingerprint ::
          {:digest, integer} | {:stat, non_neg_integer, non_neg_integer} | :fresh | :missing

  @doc """
  Aggregates JS imports from all Elixir modules referenced by the given MFAs,
  skipping the modules whose bindings another bundle already registers. The module info PLT says which
  modules declare imports; with nil, every module is asked.
  Returns a map with:
  - `:imports` — unique imports with generated `$1`, `$2`, ... aliases for JS import statements
  - `:bindings` — per-module map of user alias to generated alias for `__bindings__` on module proxies
  """
  @spec aggregate_js_imports(list(mfa), PLT.t(), PLT.t() | nil, MapSet.t(module)) :: %{
          imports: list(%{from: String.t(), export: String.t(), alias: String.t()}),
          bindings: %{module => %{String.t() => String.t()}}
        }
  def aggregate_js_imports(mfas, ir_plt, module_info_plt, excluded_modules \\ MapSet.new()) do
    modules_with_imports =
      mfas
      |> list_js_import_modules(ir_plt, module_info_plt)
      |> Enum.reject(&MapSet.member?(excluded_modules, &1))

    unique_imports =
      modules_with_imports
      |> Enum.flat_map(fn module ->
        Enum.map(module.__js_imports__(), fn %{from: from, export: export} ->
          {from, export}
        end)
      end)
      |> Enum.uniq()
      |> Enum.sort()

    alias_map =
      unique_imports
      |> Enum.with_index(1)
      |> Map.new(fn {{from, export}, index} -> {{from, export}, "$#{index}"} end)

    imports =
      Enum.map(unique_imports, fn {from, export} ->
        %{from: from, export: export, alias: alias_map[{from, export}]}
      end)

    bindings =
      Map.new(modules_with_imports, fn module ->
        module_bindings =
          Map.new(module.__js_imports__(), fn %{as: as, from: from, export: export} ->
            {as, alias_map[{from, export}]}
          end)

        {module, module_bindings}
      end)

    %{imports: imports, bindings: bindings}
  end

  @doc """
  Whether the application versions `build_app_versions/1` computes can differ from the ones an earlier
  compile computed, given that compile's module digests diff and the project's OTP application.

  They change in two ways. A module of an application appears in or disappears from the call graph,
  which takes an added or a removed module. Or an application's version changes, which for a
  dependency comes with its modules being recompiled, so they show up as edited. An edit to the
  project's own modules does neither, which is what an ordinary save is, so the kept versions stand.

  A module of no application, or of a sibling application in an umbrella, counts as not the
  project's: recomputing then is safe, and cheap next to being wrong.
  """
  @spec app_versions_changed?(map, atom) :: boolean
  def app_versions_changed?(module_digests_diff, otp_app) do
    module_digests_diff.added_modules != [] or module_digests_diff.removed_modules != [] or
      Enum.any?(
        module_digests_diff.edited_modules,
        &(Application.get_application(&1) != otp_app)
      )
  end

  @doc """
  Returns the version of each OTP application the given call graph reaches, keyed by application
  name and sorted by it.

  A stacktrace frame names the application its module belongs to and that application's version,
  the way the server renders one, and this is where the client reads the version from.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/build_app_versions_1/README.md
  """
  @spec build_app_versions(CallGraph.t()) :: keyword(String.t())
  def build_app_versions(call_graph) do
    call_graph
    |> CallGraph.vertices()
    |> Enum.map(&CallGraph.vertex_module/1)
    |> Enum.uniq()
    |> Enum.map(&Application.get_application/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map(fn app -> {app, Application.spec(app, :vsn)} end)
    |> Enum.reject(fn {_app, vsn} -> is_nil(vsn) end)
    |> Enum.map(fn {app, vsn} -> {app, to_string(vsn)} end)
    |> Enum.sort()
  end

  @doc """
  Returns what every bundle depends on besides the modules it carries, apart from Hologram's own
  modules (see `build_bundle_inputs/2`): the client stack traces setting (bundles built with it on
  register module metadata and app versions), the mtime and size of each of Hologram's JavaScript
  sources under the `:js_dir` opt (esbuild copies them into every bundle) and the digest of
  `package.json` in the `:assets_dir` opt (which pins esbuild).

  The JavaScript sources are compared by mtime and size rather than by content: they belong to a
  dependency, which changes with an upgrade or a fetch, never within a second of a compile.
  """
  @spec build_bundle_inputs(T.opts()) :: %{
          client_stacktraces?: boolean,
          js_sources: [{String.t(), integer, non_neg_integer}],
          package_json_digest: binary
        }
  def build_bundle_inputs(opts) do
    %{
      client_stacktraces?: Hologram.client_stacktraces?(),
      js_sources: list_js_sources(opts[:js_dir]),
      package_json_digest: get_package_json_digest(opts[:assets_dir])
    }
  end

  @doc """
  Returns what every bundle depends on besides the modules it carries: the inputs that need no
  module (see `build_bundle_inputs/1`) and the digests of Hologram's own modules, the ones compiled
  from its lib dir, from the given module info PLT (the encoder and the transformer decide what a
  module encodes to). Two compiles whose inputs are equal make the same bundle from the same
  modules; the compile task rebuilds every bundle when the inputs differ from the ones its kept
  bundles were built with (see `Hologram.Compiler.Cache.forget_bundles/0`).
  """
  @spec build_bundle_inputs(PLT.t(), T.opts()) :: %{
          client_stacktraces?: boolean,
          hologram_modules: [{module, integer}],
          js_sources: [{String.t(), integer, non_neg_integer}],
          package_json_digest: binary
        }
  def build_bundle_inputs(module_info_plt, opts) do
    opts
    |> build_bundle_inputs()
    |> Map.put(:hologram_modules, list_hologram_module_digests(module_info_plt))
  end

  @doc """
  Builds the call graph of all modules in the project.
  """
  @spec build_call_graph :: CallGraph.t()
  def build_call_graph do
    build_call_graph(build_ir_plt())
  end

  @doc """
  Builds the call graph of all modules in the given IR PLT, reading its module facts from a module info
  PLT built on the spot. That PLT stays up for as long as the call graph is used (it is linked to the
  calling process, like every PLT); the compile task builds its own instead and passes it to
  `build_call_graph/2`.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/build_call_graph_1/README.md
  """
  @spec build_call_graph(PLT.t()) :: CallGraph.t()
  def build_call_graph(ir_plt) do
    build_call_graph(ir_plt, build_module_info_plt!(PLT.start(), nil))
  end

  @doc """
  Builds the call graph of all modules in the given IR PLT with the given module info PLT as its module facts.
  """
  @spec build_call_graph(PLT.t(), PLT.t()) :: CallGraph.t()
  def build_call_graph(ir_plt, module_info_plt) do
    call_graph = CallGraph.start(module_info_plt: module_info_plt)

    ir_plt
    |> PLT.get_all()
    |> TaskUtils.map_concurrently(fn {_module, ir} -> CallGraph.build(call_graph, ir) end)

    CallGraph.add_non_discoverable_edges(call_graph)
  end

  @doc """
  Builds IR persistent lookup table (PLT) of all modules in the project.
  Pass `modules:` to build IR for exactly those modules instead of listing them; the compile task passes the
  module info PLT's keys.
  Pass `plt:` to fill an existing PLT instead of starting one; the compile task passes the PLT it keeps between
  compiles.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/build_ir_plt_1/README.md
  """
  @spec build_ir_plt(T.opts()) :: PLT.t()
  # credo:disable-for-lines:26 Credo.Check.Refactor.Nesting
  # The above Credo check is disabled because the function is optimised this way
  def build_ir_plt(opts \\ []) do
    ir_plt = opts[:plt] || PLT.start(opts)

    modules = opts[:modules] || Reflection.list_elixir_modules()

    # Processing modules in chunks of 2 improves performance by ~7%
    # (determined experimentally)
    chunk_size = 2

    # TODO: Remove this flag and call :code.which/1 directly below when
    # resolve_beam_source/2 goes (see the removal note there).
    umbrella? = Reflection.umbrella?()

    modules
    |> Enum.chunk_every(chunk_size)
    |> TaskUtils.map_concurrently(fn module_chunk ->
      Enum.each(module_chunk, fn module ->
        beam_source = resolve_beam_source(module, umbrella?)

        if beam_source do
          ir = IR.for_module(module, beam_source)
          PLT.put(ir_plt, module, ir)
        end
      end)
    end)

    ir_plt
  end

  @doc """
  Builds the IR of the given modules that the IR PLT does not hold yet, and returns the PLT. The compile task
  calls it for the modules it is about to read, once the call graph says which they are.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/build_missing_ir!_2/README.md
  """
  @spec build_missing_ir!(PLT.t(), [module]) :: PLT.t()
  def build_missing_ir!(ir_plt, modules) do
    missing_modules = Enum.reject(modules, &PLT.member?(ir_plt, &1))
    build_ir_plt(plt: ir_plt, modules: missing_modules)
  end

  @doc """
  Builds a persistent lookup table (PLT) holding, for every Elixir module in the project, the info the compiler
  needs before building IR: see `Hologram.Reflection.beam_info/1` for the entry shape.

  Each module's BEAM is read once. A module whose entry in `old_plt` has the same mtime and size as its BEAM
  now, and whose BEAM was last written at least a second before `dumped_at` (the mtime of the dump `old_plt`
  was loaded from, in posix seconds), reuses that entry without reading the BEAM. Pass nil as `dumped_at` to
  read every BEAM.
  """
  @spec build_module_info_plt!(PLT.t(), non_neg_integer | nil, T.opts()) :: PLT.t()
  def build_module_info_plt!(old_plt, dumped_at, opts \\ []) do
    new_plt = PLT.start(opts)

    # TODO: Remove this flag and the argument it feeds to
    # rebuild_module_info_plt_entry!/5 when resolve_beam_source/2 goes (see
    # the removal note there).
    umbrella? = Reflection.umbrella?()

    TaskUtils.map_concurrently(
      Reflection.list_candidate_modules(),
      &rebuild_module_info_plt_entry!(&1, old_plt, dumped_at, new_plt, umbrella?)
    )

    new_plt
  end

  @doc """
  Returns the stack trace metadata of every module the given module info PLT holds a source path
  for: its application and its source file relative to the root of the code that compiled it, the
  form `Hologram.Compiler.Encoder.encode_module_metadata_registration/2` renders. Computed once
  per compile, so the bundles look each module up instead of asking the VM about it per bundle.
  """
  @spec build_module_metadata(PLT.t()) :: %{module => %{app: atom | nil, file: String.t()}}
  def build_module_metadata(module_info_plt) do
    apps = Reflection.list_module_applications()
    root_dir = Reflection.root_dir()

    for {module, %{source_path: source_path}} when is_binary(source_path) <-
          PLT.get_all(module_info_plt),
        into: %{} do
      {module, %{app: apps[module], file: Reflection.relative_source_path(source_path, root_dir)}}
    end
  end

  @doc """
  Builds page digest PLT, where the keys represent page modules,
  and the values are the digests of their JavaScript bundles (esbuild's content hashes).
  """
  @spec build_page_digest_plt(list(map), T.opts()) :: {PLT.t(), T.file_path()}
  def build_page_digest_plt(bundle_info, opts) do
    page_digest_plt_items =
      for %{bundle_name: "page", entry_name: page_module, digest: digest} <- bundle_info,
          do: {page_module, digest}

    page_digest_plt = PLT.start(items: page_digest_plt_items, supervisor: opts[:supervisor])

    page_digest_plt_dump_path =
      Path.join([opts[:build_dir], Reflection.page_digest_plt_dump_file_name()])

    {page_digest_plt, page_digest_plt_dump_path}
  end

  @doc """
  Builds JavaScript code for the given Hologram page.

  The page's reachable MFAs are given (see `CallGraph.list_page_mfas/5`), so that a caller building
  many pages can encode their functions first with `encode_reachable_functions/5` and render every
  page from the encode PLT.

  ## Options

    * `:js_dir` - the directory of Hologram's JavaScript sources, which the page script imports
      from (required).
    * `:module_info_plt` - the module info PLT the bundled modules are classified from; without it
      each module is asked, which reads the BEAM of a module that is not loaded (default: none).
    * `:module_metadata` - the stack trace metadata of modules, as `build_module_metadata/1` returns
      it; the modules it does not hold are read from the loaded modules (default: none).
    * `:runtime_js_binding_modules` - modules whose JS imports are skipped when the imports are
      aggregated, because the runtime script, which every page loads, already registers their
      bindings (default: none).

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/build_page_js_5/README.md
  """
  @spec build_page_js([mfa], PLT.t(), PLT.t(), MapSet.t(mfa), T.opts()) :: String.t()
  def build_page_js(mfas, ir_plt, encode_plt, async_mfas, opts) do
    js_dir = Keyword.fetch!(opts, :js_dir)
    runtime_js_binding_modules = Keyword.get(opts, :runtime_js_binding_modules, MapSet.new())

    %{imports: imports, bindings: bindings} =
      aggregate_js_imports(mfas, ir_plt, opts[:module_info_plt], runtime_js_binding_modules)

    import_statements =
      imports
      |> render_js_import_statements()
      |> render_block()

    js_bindings_registration_call =
      bindings
      |> render_js_bindings_registration_call()
      |> render_block()

    erlang_js_dir = Path.join(js_dir, "erlang")

    erlang_function_defs =
      mfas
      |> render_erlang_function_defs(ir_plt, erlang_js_dir)
      |> render_block()

    elixir_function_defs =
      mfas
      |> render_elixir_function_defs(ir_plt, encode_plt, async_mfas, opts[:module_info_plt])
      |> render_block()

    module_metadata_registration =
      mfas
      |> render_module_metadata_registration(ir_plt, opts[:module_metadata])
      |> render_block()

    """
    "use strict";

    import PerformanceTimer from "#{js_dir}/performance_timer.mjs";#{import_statements}

    const startTime = performance.now();

    globalThis.Hologram.pageReachableFunctionDefs = (deps) => {
      const {
        Bitstring,
        ERTS,
        HologramBoxedError,
        HologramInterpreterError,
        Interpreter,
        MemoryStorage,
        Type,
        Utils,
      } = deps;#{module_metadata_registration}#{js_bindings_registration_call}#{erlang_function_defs}#{elixir_function_defs}
    }

    globalThis.Hologram.pageScriptLoaded = true;
    document.dispatchEvent(new CustomEvent("hologram:pageScriptLoaded"));

    console.debug("Hologram: page script executed in", PerformanceTimer.diff(startTime));\
    """
  end

  @doc """
  Grows the call graph until it holds every module the pages, the runtime and the broadcast callers
  reach (see `CallGraph.build_reach/3`), building the IR of each module the walk asks for into the IR
  PLT first, and returns the modules built. The walk asks only for modules the graph's module info
  PLT holds, so each has a beam to build IR from.
  """
  @spec build_reach!(CallGraph.t(), PLT.t(), map) :: [module]
  def build_reach!(call_graph, ir_plt, graph_diff) do
    CallGraph.build_reach(call_graph, graph_diff, fn modules ->
      build_missing_ir!(ir_plt, modules)
      TaskUtils.map_concurrently(modules, &CallGraph.build_for_module(call_graph, ir_plt, &1))
    end)
  end

  @doc """
  Builds Hologram runtime JavaScript source code.

  ## Options

    * `:js_dir` - the directory of Hologram's JavaScript sources, which the runtime script imports
      from (required).
    * `:module_info_plt` - the module info PLT the bundled modules are classified from; without it
      each module is asked, which reads the BEAM of a module that is not loaded (default: none).
    * `:module_metadata` - the stack trace metadata of modules, as `build_module_metadata/1` returns
      it; the modules it does not hold are read from the loaded modules (default: none).
  """
  @spec build_runtime_js(
          list(mfa),
          PLT.t(),
          PLT.t(),
          MapSet.t(mfa),
          keyword(String.t()),
          T.opts()
        ) :: String.t()
  def build_runtime_js(runtime_mfas, ir_plt, encode_plt, async_mfas, app_versions, opts) do
    js_dir = Keyword.fetch!(opts, :js_dir)

    %{imports: imports, bindings: bindings} =
      aggregate_js_imports(runtime_mfas, ir_plt, opts[:module_info_plt])

    import_statements =
      imports
      |> render_js_import_statements()
      |> render_block()

    # A module bundled into the runtime script registers its JS bindings here, because
    # remove_runtime_mfas!/2 takes its MFAs out of every page graph, so no page bundle
    # can register them.
    js_bindings_registration_call =
      bindings
      |> render_js_bindings_registration_call()
      |> render_block()

    erlang_function_defs =
      runtime_mfas
      |> render_erlang_function_defs(ir_plt, Path.join(js_dir, "erlang"))
      |> render_block()

    elixir_function_defs =
      runtime_mfas
      |> render_elixir_function_defs(ir_plt, encode_plt, async_mfas, opts[:module_info_plt])
      |> render_block()

    module_metadata_registration =
      runtime_mfas
      |> render_module_metadata_registration(ir_plt, opts[:module_metadata])
      |> render_block()

    manually_ported_clause_heads =
      ir_plt
      |> render_manually_ported_clause_heads()
      |> render_block()

    """
    "use strict";

    import Bitstring from "#{js_dir}/bitstring.mjs";
    import ERTS from "#{js_dir}/erts.mjs";
    import Hologram from "#{js_dir}/hologram.mjs";
    import HologramBoxedError from "#{js_dir}/errors/boxed_error.mjs";
    import HologramInterpreterError from "#{js_dir}/errors/interpreter_error.mjs";
    import Interpreter from "#{js_dir}/interpreter.mjs";
    import MemoryStorage from "#{js_dir}/memory_storage.mjs";
    import PerformanceTimer from "#{js_dir}/performance_timer.mjs";
    import Type from "#{js_dir}/type.mjs";
    import Utils from "#{js_dir}/utils.mjs";#{import_statements}

    const startTime = PerformanceTimer.start();

    globalThis.Hologram.config = #{client_config()};

    ERTS.appVersions = #{render_app_versions(app_versions)};#{module_metadata_registration}#{js_bindings_registration_call}#{erlang_function_defs}#{elixir_function_defs}#{manually_ported_clause_heads}

    document.addEventListener("hologram:pageScriptLoaded", () => Hologram.run());

    if (globalThis.Hologram.pageScriptLoaded) {
      document.dispatchEvent(new CustomEvent("hologram:pageScriptLoaded"));
    }

    console.debug("Hologram: runtime script executed in", PerformanceTimer.diff(startTime));\
    """
  end

  @doc """
  Bundles multiple entry files, each as `bundle/4` does. An entry is given as
  `{entry_name, entry_file_path, bundle_name}`, the entry name `nil` for a bundle name with a single
  entry.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/bundle_2/README.md
  """
  @spec bundle(list({module | nil, T.file_path(), String.t()}), T.opts()) :: list(map)
  def bundle(entry_files_info, opts) do
    TaskUtils.map_concurrently(entry_files_info, fn {entry_name, entry_file_path, bundle_name} ->
      bundle(entry_name, entry_file_path, bundle_name, opts)
    end)
  end

  @doc """
  Bundles the given entry file with esbuild, which names the output `<bundle_name>-<hash>.js` and
  its source map `<bundle_name>-<hash>.js.map` by the content hash, with the entry name, a module
  written without its `Elixir.` prefix, between the bundle name and the hash when one is given: a
  bundle name shared by many entries (the page bundles) needs it to tell them apart, one with a
  single entry (the runtime) does not. The returned digest is the hash.

  The returned `js_inputs` are the files esbuild read for the bundle besides the entry file,
  Hologram's own sources under the `:js_dir` opt and the packages under the `:node_modules_path`
  opt, with their fingerprints (see `fingerprint_js_inputs/2`), taken against the time esbuild
  started: a bundle inlines them, and a kept bundle whose files moved must be built again.
  """
  @spec bundle(module | nil, T.file_path(), String.t(), T.opts()) :: map
  # sobelow_skip ["CI.System"]
  def bundle(entry_name, entry_file_path, bundle_name, opts) do
    # esbuild names the bundle and its source map by their content hash and writes the source map
    # comment to match, so neither file is read back or rewritten. Each bundle gets its own output
    # dir: the name is only known once esbuild has run, so the dir is listed for it, and it is
    # recreated so that a bundle left there by a run that failed the size check is not listed too.
    output_name = bundle_output_name(bundle_name, entry_name)
    output_dir = Path.join(opts[:tmp_dir], "#{output_name}.output")
    FileUtils.recreate_dir(output_dir)
    metafile_path = Path.join(output_dir, "meta.json")

    esbuild_cmd = [
      "#{output_name}=#{entry_file_path}",
      "--bundle",
      "--entry-names=[name]-[hash]",
      "--log-level=warning",
      "--metafile=#{metafile_path}",
      "--minify",
      "--outdir=#{output_dir}",
      "--sourcemap",
      "--sources-content=true",
      "--target=es2021"
    ]

    # Both the workspace root's and the OTP app's assets/node_modules go on
    # NODE_PATH (identical in single-app projects, hence deduplicated).
    # Non-existent dirs are silently ignored by Node.
    workspace_and_otp_app_node_modules_paths =
      [Reflection.root_dir(), Reflection.otp_app_dir()]
      |> Enum.uniq()
      |> Enum.map(&Path.join([&1, "assets", "node_modules"]))

    node_path =
      Enum.join(
        [opts[:node_modules_path] | workspace_and_otp_app_node_modules_paths],
        PathUtils.env_path_separator()
      )

    esbuild_opts = [
      env: [{"NODE_PATH", node_path}],
      parallelism: true
    ]

    # A file whose mtime is not older than this may have been written after esbuild read it (see
    # list_bundle_js_inputs/3).
    started_at = System.os_time(:second)

    {_exit_msg, exit_status} =
      SystemUtils.cmd_cross_platform(opts[:esbuild_bin_path], esbuild_cmd, esbuild_opts)

    if exit_status != 0 do
      raise RuntimeError,
        message:
          "esbuild bundler failed for entry file: #{entry_file_path} (probably there were JavaScript syntax errors)"
    end

    [bundle_file_name] =
      output_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".js"))

    output_bundle_path = Path.join(output_dir, bundle_file_name)

    maybe_ensure_bundle_within_size_limit!(output_name, output_bundle_path)

    digest =
      bundle_file_name
      |> Path.basename(".js")
      |> String.replace_prefix("#{output_name}-", "")

    static_bundle_path = Path.join(opts[:static_dir], bundle_file_name)
    static_source_map_path = static_bundle_path <> ".map"

    File.rename!(output_bundle_path, static_bundle_path)
    File.rename!(output_bundle_path <> ".map", static_source_map_path)

    # Read once and removed, so that the output dir is left empty, as the bundle and its source map
    # leave it.
    js_inputs = list_bundle_js_inputs(metafile_path, started_at, opts)
    File.rm!(metafile_path)

    %{
      bundle_name: bundle_name,
      digest: digest,
      entry_name: entry_name,
      js_inputs: js_inputs,
      static_bundle_path: static_bundle_path,
      static_source_map_path: static_source_map_path
    }
  end

  @doc """
  Returns the client config the runtime bundle sets as `globalThis.Hologram.config`: whether the
  error overlay is on, whether live reload is (it runs in dev only, and in test, so that the feature
  tests can drive it, as the SSE stream's live reload subscription does), and whether client stack
  traces are. `liveReload` lets the client load a page afresh when it holds that page's code in an
  older version (see live_reload.mjs). The runtime bundle carries it as written here, so the
  compile task keeps a runtime bundle only while this is what it was built with.
  """
  @spec client_config() :: String.t()
  def client_config do
    live_reload? = Hologram.env() in [:dev, :test]

    "{errorOverlay: #{Hologram.client_error_overlay?()}, liveReload: #{live_reload?}, " <>
      "stacktraces: #{Hologram.client_stacktraces?()}}"
  end

  @doc """
  Creates the page bundle entry files, given each page's reachable MFAs (see `list_mfas_by_page/5`).
  The functions of all the given pages are encoded into the encode PLT first, with one IR read per
  module (`encode_reachable_functions/5`), and then each page is rendered from that cache, so a
  module's IR is read once for all the pages of one call. The compile task calls it once per batch;
  a function already in the encode PLT, encoded for an earlier batch or an earlier compile, is not
  encoded again. The module info PLT is taken from the `module_info_plt:` opt.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/create_page_entry_files_6/README.md
  """
  @spec create_page_entry_files(
          list({module, list(mfa)}),
          PLT.t(),
          PLT.t(),
          MapSet.t(mfa),
          MapSet.t(module),
          T.opts()
        ) :: list({module, T.file_path()})
  def create_page_entry_files(
        mfas_by_page,
        ir_plt,
        encode_plt,
        async_mfas,
        runtime_js_binding_modules,
        opts
      ) do
    module_info_plt = opts[:module_info_plt]

    mfas_by_page
    |> Enum.flat_map(fn {_page_module, mfas} -> mfas end)
    |> encode_reachable_functions(ir_plt, encode_plt, async_mfas, module_info_plt)

    TaskUtils.map_concurrently(mfas_by_page, fn {page_module, mfas} ->
      entry_name = Reflection.module_name(page_module)

      entry_file_path =
        mfas
        |> build_page_js(ir_plt, encode_plt, async_mfas,
          js_dir: opts[:js_dir],
          module_info_plt: module_info_plt,
          module_metadata: opts[:module_metadata],
          runtime_js_binding_modules: runtime_js_binding_modules
        )
        |> create_entry_file(entry_name, opts[:tmp_dir])

      {page_module, entry_file_path}
    end)
  end

  @doc """
  Creates runtime bundle entry file.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/create_runtime_entry_file_5/README.md
  """
  @spec create_runtime_entry_file(
          list(mfa),
          PLT.t(),
          PLT.t(),
          MapSet.t(mfa),
          keyword(String.t()),
          T.opts()
        ) :: T.file_path()
  def create_runtime_entry_file(runtime_mfas, ir_plt, encode_plt, async_mfas, app_versions, opts) do
    runtime_mfas
    |> build_runtime_js(ir_plt, encode_plt, async_mfas, app_versions,
      js_dir: opts[:js_dir],
      module_info_plt: opts[:module_info_plt],
      module_metadata: opts[:module_metadata]
    )
    |> create_entry_file("runtime", opts[:tmp_dir])
  end

  @doc """
  Deletes from the encode PLT the entries of the given modules' functions, and returns the PLT. A
  module's functions are encoded again from its IR once it was edited, and are gone with it once it
  was removed. Reads the keys only, never the values. Given no module, it reads nothing.
  """
  @spec delete_module_encodings(PLT.t(), [module]) :: PLT.t()
  def delete_module_encodings(encode_plt, []), do: encode_plt

  def delete_module_encodings(encode_plt, modules) do
    dropped_modules = MapSet.new(modules)

    encode_plt
    |> PLT.keys()
    |> Enum.filter(fn {module, _function, _arity} -> MapSet.member?(dropped_modules, module) end)
    |> Enum.each(&PLT.delete(encode_plt, &1))

    encode_plt
  end

  @doc """
  Deletes the IR of the given modules from the IR PLT and returns the PLT. The compile task calls it
  with the removed and edited modules of a compile: a removed module's IR is not read again, and an
  edited module's is built again from its new beam, with `build_missing_ir!/2`, by whatever reads it
  in this compile or a later one.
  """
  @spec delete_module_ir(PLT.t(), [module]) :: PLT.t()
  def delete_module_ir(ir_plt, modules) do
    TaskUtils.map_concurrently(modules, &PLT.delete(ir_plt, &1))
    ir_plt
  end

  @doc """
  Compares two module info PLTs by digest and returns the added, removed, and edited modules lists.
  An entry whose mtime or size moved but whose digest did not is not an edit.
  """
  @spec diff_module_info_plts(PLT.t(), PLT.t()) :: %{
          added_modules: list(module),
          removed_modules: list(module),
          edited_modules: list(module)
        }
  def diff_module_info_plts(old_plt, new_plt) do
    old_infos = PLT.get_all(old_plt)
    new_infos = PLT.get_all(new_plt)

    added_modules =
      for {module, _info} <- new_infos, not Map.has_key?(old_infos, module), do: module

    edited_modules =
      for {module, %{digest: digest}} <- new_infos,
          edited_module?(old_infos, module, digest),
          do: module

    removed_modules =
      for {module, _info} <- old_infos, not Map.has_key?(new_infos, module), do: module

    %{
      added_modules: added_modules,
      removed_modules: removed_modules,
      edited_modules: edited_modules
    }
  end

  @doc """
  Encodes into the encode PLT every function of the given MFAs that is not there yet, reading each
  module's IR once however many entry files reach it. Erlang modules are skipped, and so are
  protocol modules, whose dispatcher functions depend on the entry file and are encoded per entry
  file; the module info PLT says which modules are protocols without touching their code paths.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/encode_reachable_functions_5/README.md
  """
  @spec encode_reachable_functions([mfa], PLT.t(), PLT.t(), MapSet.t(mfa), PLT.t() | nil) :: :ok
  def encode_reachable_functions(mfas, ir_plt, encode_plt, async_mfas, module_info_plt) do
    mfas
    |> Enum.uniq()
    |> group_mfas_by_module()
    # Checked once per module, not per MFA: the lists of many pages repeat the same MFAs.
    |> Enum.filter(fn {module, _module_mfas} ->
      Reflection.elixir_module?(module, ir_plt) and
        not Reflection.protocol?(module, module_info_plt)
    end)
    |> TaskUtils.map_concurrently(fn {module, module_mfas} ->
      missing =
        module_mfas
        |> Enum.map(fn {_module, function, arity} -> {function, arity} end)
        |> Enum.reject(&function_encoded?(encode_plt, module, &1))

      if missing != [] do
        context = %Context{async_mfas: async_mfas, ir_plt: ir_plt, module: module}
        encode_missing_module_functions(missing, module, ir_plt, encode_plt, context)
      end
    end)

    :ok
  end

  @doc """
  Returns the fingerprint of each given file, keyed by its path: `{:digest, digest}` of the content
  for a file outside any `node_modules` dir (the app's own JavaScript, which the dev saves,
  sometimes within the second of a compile), `{:stat, mtime, size}` for a file under one (packages
  change on install, never within a second of a compile, and a bundle can read dozens of them),
  `:fresh` for a file whose mtime is not older than `started_at` in posix seconds (it may have been
  written after the reader that started then read it, so its record must never match; nil takes no
  file as fresh) and `:missing` for a file that is not there or cannot be read (one removed between
  its stat and its read included). A bundle records the fingerprints of the files esbuild read for
  it (see `bundle/4`), and the compile task compares them with the fingerprints now to find the
  bundles to rebuild.
  """
  @spec fingerprint_js_inputs([String.t()], non_neg_integer | nil) :: %{
          String.t() => js_input_fingerprint
        }
  def fingerprint_js_inputs(paths, started_at) do
    Map.new(paths, &{&1, fingerprint_js_input(&1, started_at)})
  end

  @doc """
  Extracts JavaScript source code for the given ported Erlang function.

  Returns the JavaScript function code if it exists in the corresponding .mjs file,
  or nil if the file or function doesn't exist.

  ## Examples

      iex> get_erlang_function_js(:erlang, :+, 2, "/path/to/erlang")
      "(left, right) => { ... }"

      iex> get_erlang_function_js(:maps, :get, 2, "/path/to/erlang")
      "(key, map) => { ... }"

      iex> get_erlang_function_js(:erlang, :not_implemented, 2, "/path/to/erlang")
      nil
  """
  @spec get_erlang_function_js(module, atom, non_neg_integer, T.file_path()) :: String.t() | nil
  def get_erlang_function_js(module, function, arity, erlang_js_dir) do
    file_path =
      if module == :erlang do
        "#{erlang_js_dir}/erlang.mjs"
      else
        "#{erlang_js_dir}/#{module}.mjs"
      end

    if File.exists?(file_path) do
      extract_erlang_function_js(file_path, function, arity)
    else
      nil
    end
  end

  @doc """
  Groups the given MFAs by module.
  """
  @spec group_mfas_by_module(list(mfa)) :: %{module => mfa}
  def group_mfas_by_module(mfas) do
    Enum.group_by(mfas, fn {module, _function, _arity} -> module end)
  end

  @doc """
  Installs JavaScript deps which are specified in package.json located in assets_dir.
  Saves the package.json digest to package_json_digest.bin file in build_dir.
  """
  @spec install_js_deps(T.file_path(), T.file_path()) :: :ok
  # sobelow_skip ["CI.System"]
  def install_js_deps(assets_dir, build_dir) do
    # Run from the project root, not from inside assets_dir, so version managers like
    # asdf/mise resolve the Node.js version from the consuming project's config rather
    # than any .tool-versions inside a git-checked-out dependency. npm still installs
    # into assets_dir via --prefix.
    opts = [into: IO.stream(:stdio, :line)]

    {_result, exit_status} =
      SystemUtils.cmd_cross_platform("npm", ["install", "--prefix", assets_dir], opts)

    if exit_status != 0 do
      raise RuntimeError, message: "npm install command failed"
    end

    package_json_digest = get_package_json_digest(assets_dir)
    package_json_digest_path = Path.join(build_dir, "package_json_digest.bin")

    File.write!(package_json_digest_path, package_json_digest)
  end

  @doc """
  Whether a bundle's recorded inputs (see `bundle/4`) no longer match the files: any recorded file
  whose fingerprint differs from its fingerprint now in `js_fingerprints` (see
  `fingerprint_js_inputs/2`), or that `js_fingerprints` does not hold. Each bundle is compared on
  its own record: two bundles can hold different fingerprints of one file, when it was saved
  between the two builds, and only the one that read the old content is stale.
  """
  @spec js_inputs_changed?(%{String.t() => js_input_fingerprint}, %{
          String.t() => js_input_fingerprint
        }) :: boolean
  def js_inputs_changed?(js_inputs, js_fingerprints) do
    Enum.any?(js_inputs, fn {path, fingerprint} ->
      Map.get(js_fingerprints, path) != fingerprint
    end)
  end

  @doc """
  Returns every component usage found in the given IR, as `{component_module, props, has_spread?}`
  tuples, in the order they appear in the template.

  `props` holds one entry per prop written at the usage, without the framework's own `$`-prefixed
  entries, as `{name, {:ok, value}}` when the value is known without running anything, and
  `{name, :unknown}` otherwise. `has_spread?` says whether the usage carries a `...{expr}` spread,
  which makes its set of props impossible to know before the expression has a value.

  Dynamic tags (`<{@module} />`) are skipped - the component module itself is a runtime value there.

  ## Examples

      iex> list_component_usages(IR.for_module(MyApp.HomePage))
      [{MyApp.Card, [{"size", {:ok, :small}}, {"count", :unknown}], false}]
  """
  @spec list_component_usages(IR.t()) ::
          list({module, list({String.t(), {:ok, any} | :unknown}), boolean})
  def list_component_usages(ir) do
    ir
    |> collect_component_usages([])
    |> Enum.reverse()
  end

  @doc """
  Lists the component modules recorded in the given module info PLT, sorted by name.
  """
  @spec list_components(PLT.t()) :: list(module)
  def list_components(module_info_plt) do
    list_modules_where(module_info_plt, :component?)
  end

  @doc """
  Lists the modules whose IR the entry files rendered from the given MFAs read: the modules of those MFAs and
  of the manually ported MFAs (the runtime entry file renders their clause heads), each once. Only the modules
  the module info PLT holds are listed, since the IR PLT is built for those alone (an Erlang module has no IR).
  """
  @spec list_ir_modules([mfa], PLT.t()) :: [module]
  def list_ir_modules(mfas, module_info_plt) do
    [mfas, CallGraph.manually_ported_elixir_mfas()]
    |> Stream.concat()
    |> Stream.map(fn {module, _function, _arity} -> module end)
    |> Stream.uniq()
    |> Enum.filter(&PLT.member?(module_info_plt, &1))
  end

  @doc """
  Lists the Elixir modules referenced by the given MFAs that declare JS imports. The IR PLT tells
  the Elixir modules apart from the Erlang ones, and the module info PLT says which of them declare
  imports without touching their code paths; with nil, every module is asked.
  """
  @spec list_js_import_modules(list(mfa), PLT.t(), PLT.t() | nil) :: list(module)
  def list_js_import_modules(mfas, ir_plt, module_info_plt) do
    mfas
    |> filter_elixir_mfas(ir_plt)
    |> Enum.map(fn {module, _function, _arity} -> module end)
    |> Enum.uniq()
    |> Enum.filter(&(Reflection.js_imports?(&1, module_info_plt) and &1.__js_imports__() != []))
  end

  @doc """
  Lists the modules whose IR and function encodings a compile keeps: the modules the runtime entry file
  reads (see `list_ir_modules/2`) and the modules each page reaches, each once. A page's modules are
  given as the `MapSet` of the modules of its reachable MFAs, as a page state keeps it, so they include
  the page itself: every page is kept, and a component no page reaches is not. Only the modules the
  module info PLT holds are listed, since the IR PLT is built for those alone.
  """
  @spec list_kept_modules([mfa], [{module, MapSet.t(module)}], PLT.t()) :: [module]
  def list_kept_modules(runtime_mfas, modules_by_page, module_info_plt) do
    page_reached_modules =
      modules_by_page
      |> Enum.reduce(MapSet.new(), fn {_page_module, modules}, acc ->
        MapSet.union(acc, modules)
      end)
      |> Enum.filter(&PLT.member?(module_info_plt, &1))

    runtime_mfas
    |> list_ir_modules(module_info_plt)
    |> Enum.concat(page_reached_modules)
    |> Enum.uniq()
  end

  @doc """
  Lists, for each page, the MFAs reachable from it (see `CallGraph.list_page_mfas/5`), sharing the call
  graph's graph with the page tasks (see `CallGraph.with_shared_graph/2`) and the server callback
  analyses they compute, for this call. The compile task lists its batches with `list_mfas_by_page/5`
  against a graph and analyses it shares for the whole compile; this is for a caller that lists once.
  With no page, the graph is not read: a graph still being rebuilt is not waited for. A caller
  with no graph to give (see the compile task's pages graph) passes nil with no page. The opts are
  passed on to `CallGraph.list_page_mfas/5`: the `:gate` opt says which reflection functions the
  pages can call, and the `:flow` opt (a `Hologram.Compiler.DataFlow` context) which types and
  components the pages' server callbacks can hand to the client.
  """
  @spec list_mfas_by_page([module], CallGraph.t() | nil, T.opts()) :: [{module, [mfa]}]
  def list_mfas_by_page(page_modules, call_graph, opts \\ [])

  def list_mfas_by_page([], _call_graph, _opts), do: []

  def list_mfas_by_page(page_modules, call_graph, opts) do
    module_info_plt = CallGraph.module_info_plt(call_graph)
    analyses = PLT.start()

    try do
      CallGraph.with_shared_graph(
        call_graph,
        &list_mfas_by_page(page_modules, &1, analyses, module_info_plt, opts)
      )
    after
      PLT.stop(analyses)
    end
  end

  @doc """
  Lists, for each page, the MFAs reachable from it (see `CallGraph.list_page_mfas/5`), one task per
  page, through the reader of a shared graph (see `CallGraph.with_shared_graph/2`) and the PLT of
  server callback analyses, which the pages fill as they go: a caller listing pages in rounds, as the
  compile task does with its batches, computes each templatable's analysis once for all of them. The
  opts are passed on to `CallGraph.list_page_mfas/5` (see `list_mfas_by_page/3` about the `:gate` and
  `:flow` opts).
  """
  @spec list_mfas_by_page([module], (-> Digraph.t()), PLT.t(), PLT.t() | nil, T.opts()) ::
          [{module, [mfa]}]
  def list_mfas_by_page(page_modules, read_graph, analyses, module_info_plt, opts \\ []) do
    # The tasks get the reader, which captures only the shared graph's key: a closure that
    # captured the graph itself would copy it into every task it starts. Listing a page's MFAs is
    # a cheap graph walk.
    TaskUtils.map_concurrently(page_modules, fn page_module ->
      mfas = CallGraph.list_page_mfas(read_graph.(), page_module, analyses, module_info_plt, opts)
      {page_module, mfas}
    end)
  end

  @doc """
  Lists, for each given page, the pages among the modules it reaches, itself excluded. A link or a
  path helper in a template is a call with the page module as an argument, which reaches the page's
  module vertex and through it `__params__/0` and `__route__/0` only, so the modules of a page's
  reachable MFAs, given as the `MapSet` a page state keeps, name exactly the pages it links to, one
  hop away. A page whose modules are not given, one no compile has built, links to no page.
  """
  @spec list_page_links([{module, MapSet.t(module)}], [module]) :: %{module => MapSet.t(module)}
  def list_page_links(modules_by_page, page_modules) do
    page_set = MapSet.new(page_modules)

    links =
      Map.new(modules_by_page, fn {page_module, modules} ->
        linked_pages =
          modules
          |> MapSet.intersection(page_set)
          |> MapSet.delete(page_module)

        {page_module, linked_pages}
      end)

    Map.new(page_modules, &{&1, Map.get(links, &1, MapSet.new())})
  end

  @doc """
  Lists the page modules recorded in the given module info PLT, sorted by name.
  """
  @spec list_pages(PLT.t()) :: list(module)
  def list_pages(module_info_plt) do
    list_modules_where(module_info_plt, :page?)
  end

  @doc """
  Lists the templatables whose prop usages a compile validates: every one when no earlier validation
  is kept (`template_modules` nil), else the ones the module digests diff added or edited, and the
  ones whose template uses an added, edited or removed module, as `template_modules` (each
  templatable's used modules, from `validate_prop_usages/2`) records them. A usage's validity
  depends on its template and on the used component's props, which live in those modules' beams
  alone.
  """
  @spec list_templatables_to_validate([module], map, %{module => MapSet.t(module)} | nil) ::
          [module]
  def list_templatables_to_validate(templatable_modules, _module_digests_diff, nil) do
    templatable_modules
  end

  def list_templatables_to_validate(templatable_modules, module_digests_diff, template_modules) do
    changed_modules =
      MapSet.new(
        module_digests_diff.added_modules ++
          module_digests_diff.edited_modules ++ module_digests_diff.removed_modules
      )

    Enum.filter(templatable_modules, fn module ->
      MapSet.member?(changed_modules, module) or
        not MapSet.disjoint?(template_modules[module], changed_modules)
    end)
  end

  @doc """
  Installs JavaScript deps if package.json has changed or if the deps haven't been installed yet.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/maybe_install_js_deps_2/README.md
  """
  @spec maybe_install_js_deps(T.file_path(), T.file_path()) :: :ok | nil
  def maybe_install_js_deps(assets_dir, build_dir) do
    package_json_digest_path = Path.join(build_dir, "package_json_digest.bin")
    package_json_lock_path = Path.join(assets_dir, "package-lock.json")

    if !File.exists?(package_json_digest_path) or !File.exists?(package_json_lock_path) do
      install_js_deps(assets_dir, build_dir)
    else
      old_package_json_digest = File.read!(package_json_digest_path)
      new_package_json_digest = get_package_json_digest(assets_dir)

      if new_package_json_digest != old_package_json_digest do
        install_js_deps(assets_dir, build_dir)
      end
    end
  end

  @doc """
  Loads the module info PLT from its dump file in the build dir if the file exists, or creates an empty PLT.
  Returns the PLT, the dump path, and the dump file's mtime in posix seconds (nil when there is no dump),
  which `build_module_info_plt!/3` uses to decide which entries can be reused.
  """
  @spec maybe_load_module_info_plt(T.file_path(), T.opts()) ::
          {PLT.t(), String.t(), non_neg_integer | nil}
  def maybe_load_module_info_plt(build_dir, opts \\ []) do
    plt = PLT.start(opts)
    dump_path = Path.join(build_dir, Reflection.module_info_plt_dump_file_name())
    dumped_at = module_info_dumped_at(dump_path)

    PLT.maybe_load(plt, dump_path)

    {plt, dump_path, dumped_at}
  end

  @doc """
  Returns the mtime in posix seconds of the module info dump at the given path, which
  `build_module_info_plt!/3` takes as `dumped_at`, or nil when there is no dump.
  """
  @spec module_info_dumped_at(T.file_path()) :: non_neg_integer | nil
  def module_info_dumped_at(dump_path) do
    case File.stat(dump_path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> mtime
      {:error, _reason} -> nil
    end
  end

  @doc """
  Returns the IR of the given module from the IR PLT, building it there first when the PLT does not
  hold it (see `build_missing_ir!/2`, so that in an umbrella a module still loaded from a consolidated
  beam the code reloader deleted is read from its object code). Returns `:error` for a module that
  has no IR: an Erlang module, or one with no beam.
  """
  @spec module_ir(PLT.t(), module) :: {:ok, IR.ModuleDefinition.t()} | :error
  def module_ir(ir_plt, module) do
    with :error <- PLT.get(ir_plt, module) do
      if Reflection.elixir_module?(module) do
        build_missing_ir!(ir_plt, [module])
      end

      PLT.get(ir_plt, module)
    end
  end

  @doc """
  Splits the given pages into the ones a compile must rebuild and the ones whose bundle it can reuse.

  A page is rebuilt when the pages PLT holds no state for it (a new page, or the first compile in a
  VM), when the modules of its kept MFAs meet `reaching_modules` (see
  `Hologram.Compiler.CallGraph.list_modules_reaching/2`: every way a page's bundle depends on a
  module is a path in the call graph from a vertex of the page, or of a component it renders, to that
  module), when the bundle its kept state describes or that bundle's source map is no longer on disk
  (a build dir can lose bundles to another build env sharing the static dir), or when that bundle
  belongs to a static dir other than the given one. A page whose bundle's recorded inputs no longer
  match `js_fingerprints`, the fingerprints of the files now, is rebuilt as well (see
  `js_inputs_changed?/2`): no beam moves when a JavaScript file a bundle inlines is edited. A page
  in `pending_pages` is rebuilt too: an earlier compile set out to build it and did not, so its kept
  bundle may predate an edit.

  Returns `{pages_to_rebuild, kept_pages}`, where the kept pages carry their state, both in the order
  the pages were given.
  """
  @spec partition_affected_pages(
          [module],
          MapSet.t(module),
          %{String.t() => js_input_fingerprint},
          MapSet.t(module),
          PLT.t(),
          T.file_path()
        ) ::
          {[module], [{module, map}]}
  def partition_affected_pages(
        page_modules,
        reaching_modules,
        js_fingerprints,
        pending_pages,
        pages_plt,
        static_dir
      ) do
    {kept_pages, pages_to_rebuild} =
      page_modules
      |> Enum.map(fn page_module ->
        page_state =
          keepable_page_state(
            pages_plt,
            page_module,
            reaching_modules,
            js_fingerprints,
            pending_pages,
            static_dir
          )

        {page_module, page_state}
      end)
      |> Enum.split_with(fn {_page_module, page_state} -> page_state end)

    {Enum.map(pages_to_rebuild, fn {page_module, nil} -> page_module end), kept_pages}
  end

  @doc """
  Returns `{pages_to_rebuild, kept_pages}`: the pages this compile must rebuild, which it lists with
  their batches (see `list_mfas_by_page/5`), and the pages whose kept bundle it can reuse, each with
  its state.

  Options:

    * `:gate` - the dynamic call gate the pages are listed with (see
      `Hologram.Compiler.DynamicCallGate`); read only with `:relist_all?`, where the kept pages are
      listed again with it, as their kept MFA lists were. Defaults to none.
    * `:pages_plt` - the PLT of page states kept by `Hologram.Compiler.Cache`.
    * `:page_mfas_plt` - the PLT of page MFA lists kept by `Hologram.Compiler.Cache`; read only with
      `:relist_all?`. A kept page it has no list for is rebuilt then.
    * `:pending_pages` - the pages an earlier compile left unbuilt (see
      `Hologram.Compiler.Cache.put_pending_pages/1`); they are rebuilt whether or not the edit reaches
      them. Defaults to none.
    * `:reaching_modules` - the modules that reach the changed ones, from
      `Hologram.Compiler.CallGraph.list_modules_reaching/2`; see `partition_affected_pages/6` for
      what makes a page affected.
    * `:js_fingerprints` - the fingerprints now of the files the kept bundles read (see
      `fingerprint_js_inputs/2`); a kept page whose recorded inputs no longer match them is
      rebuilt. Defaults to none, which only a page that recorded no input matches.
    * `:static_dir` - the dir this compile writes its bundles to; a kept bundle must live there.
    * `:relist_all?` - when the runtime bundle's MFA set, or what its dynamic calls open (see
      `Hologram.Compiler.CallGraph.runtime_dynamic_calls/2`), changed. A kept page's MFAs can then
      have moved although nothing it reaches was edited: a function that joined the runtime's set
      leaves the page's bundle, and one that left it enters, and a reflection function the runtime
      opens or closes enters or leaves it. The otherwise kept pages are listed again and those whose
      list differs from the one their bundle was built from are rebuilt, and listed again with their
      batch: few pages move, and a page's list is taken when the page is built.
    * `:rebuild_all?` - when the JS import modules the runtime registers changed. Page bundles leave
      those imports out, which their MFA lists do not show, so every page is rebuilt.

  The call graph is read only with `:relist_all?`, so a caller that passes it false may pass nil.
  """
  @spec partition_pages_to_rebuild([module], CallGraph.t() | nil, T.opts()) ::
          {[module], [{module, map}]}
  def partition_pages_to_rebuild(page_modules, call_graph, opts) do
    {pages_to_rebuild, kept_pages} =
      if opts[:rebuild_all?] do
        {page_modules, []}
      else
        partition_affected_pages(
          page_modules,
          opts[:reaching_modules],
          Keyword.get(opts, :js_fingerprints, %{}),
          Keyword.get(opts, :pending_pages, MapSet.new()),
          opts[:pages_plt],
          opts[:static_dir]
        )
      end

    if opts[:relist_all?] do
      {moved_pages, still_kept_pages} =
        relist_kept_pages(kept_pages, call_graph, opts[:page_mfas_plt], opts[:gate])

      {pages_to_rebuild ++ moved_pages, still_kept_pages}
    else
      {pages_to_rebuild, kept_pages}
    end
  end

  @doc """
  Brings the module info PLT of the last finished compile in this VM in line with the beams now, in
  place, and returns what changed: the module digests diff (as `diff_module_info_plts/2` returns it,
  each list sorted) and whether any entry changed at all (an entry whose mtime moved but whose
  digest did not is changed, but no edit).

  A module the compiler reported since the last compile (`compiled_modules`, see
  `Hologram.Compiler.Tracer.take/1`) is read, whatever its entry says. The entry of any other module
  is left where it is, unless it is a protocol's, whose consolidated beam a new implementation
  rewrites without a compile, or there is none; that one is checked against the entry's mtime and
  size, as in `build_module_info_plt!/3`, with `dumped_at` the mtime of the dump the last compile
  wrote. A module of `editable_modules` that is not among `editable_beams` now is looked up as
  `build_module_info_plt!/3` looks up every module, and loses its entry only when the VM has no beam
  for it: a deleted module is purged, while a consolidated protocol whose directory is off the code
  path for a moment (Phoenix's reloader takes it off while it recompiles) keeps its entry. Leaving
  the entries a scan into a new PLT would copy is what makes a compile that changed nothing cheap.
  """
  @spec patch_module_info_plt!(
          PLT.t(),
          non_neg_integer | nil,
          MapSet.t(module),
          list({module, charlist}),
          MapSet.t(module)
        ) :: {map, boolean}
  def patch_module_info_plt!(plt, dumped_at, editable_modules, editable_beams, compiled_modules) do
    beam_results =
      TaskUtils.map_concurrently(editable_beams, fn {module, beam_path} ->
        patch_module_info_plt_entry!(plt, module, beam_path, dumped_at, compiled_modules)
      end)

    listed_modules = MapSet.new(editable_beams, fn {module, _beam_path} -> module end)
    umbrella? = Reflection.umbrella?()

    vanished_results =
      editable_modules
      |> MapSet.difference(listed_modules)
      |> Enum.map(&patch_vanished_module_info!(plt, &1, dumped_at, umbrella?))

    results = beam_results ++ vanished_results

    diff = %{
      added_modules: list_results(results, :added),
      edited_modules: list_results(results, :edited),
      removed_modules: list_results(results, :removed)
    }

    {diff, Enum.any?(results, &(&1 != :kept))}
  end

  @doc """
  Returns the kept module metadata (see `build_module_metadata/1`) brought in line with the module
  digests diff: the entries of the removed and edited modules dropped, the entries of the added and
  edited modules built from the module info PLT, as `build_module_metadata/1` builds them. An entry
  depends on its module's beam alone, since the application tables it names do not move within a VM.
  """
  @spec patch_module_metadata(%{module => map}, map, PLT.t()) :: %{module => map}
  def patch_module_metadata(module_metadata, module_digests_diff, module_info_plt) do
    root_dir = Reflection.root_dir()

    rebuilt_entries =
      for module <- module_digests_diff.added_modules ++ module_digests_diff.edited_modules,
          {:ok, %{source_path: source_path}} when is_binary(source_path) <-
            [PLT.get(module_info_plt, module)],
          into: %{} do
        {module,
         %{
           app: module_application(module),
           file: Reflection.relative_source_path(source_path, root_dir)
         }}
      end

    module_metadata
    |> Map.drop(module_digests_diff.removed_modules ++ module_digests_diff.edited_modules)
    |> Map.merge(rebuilt_entries)
  end

  @doc """
  Deletes from the IR PLT the entries of modules not in the given list, and returns the modules it
  deleted. Reads the keys only, never the values: the table can hold gigabytes.
  """
  @spec prune_ir_plt(PLT.t(), [module]) :: [module]
  def prune_ir_plt(ir_plt, modules) do
    kept_modules = MapSet.new(modules)

    dropped_modules =
      ir_plt
      |> PLT.keys()
      |> Enum.reject(&MapSet.member?(kept_modules, &1))

    Enum.each(dropped_modules, &PLT.delete(ir_plt, &1))

    dropped_modules
  end

  @doc """
  Whether the runtime bundle must be rebuilt because its inputs differ from the ones the kept runtime
  state was built from: its MFAs, the JS import modules it registers (which every page bundle leaves
  out) and the application versions it carries. True when there is no kept state.
  """
  @spec runtime_changed?(map | nil, [mfa], MapSet.t(module), keyword(String.t())) :: boolean
  def runtime_changed?(kept_runtime, runtime_mfas, js_binding_modules, app_versions)

  def runtime_changed?(nil, _runtime_mfas, _js_binding_modules, _app_versions), do: true

  def runtime_changed?(kept_runtime, runtime_mfas, js_binding_modules, app_versions) do
    kept_runtime.mfas != runtime_mfas or
      kept_runtime.js_binding_modules != js_binding_modules or
      kept_runtime.app_versions != app_versions
  end

  @doc """
  Keeps only those IR expressions that are function definitions of the given reachable MFAs of
  the module. For protocol modules, additionally drops the consolidated impl_for/1 and
  struct_impl_for/1 clauses that return implementations not among the given reachable modules.
  Which modules are protocols and implementations is answered from the given module info PLT
  (nil to ask the modules), so no module is loaded to prune a dispatcher.
  """
  @spec prune_module_def(IR.ModuleDefinition.t(), list(mfa), MapSet.t(module), PLT.t() | nil) ::
          IR.ModuleDefinition.t()
  def prune_module_def(module_def_ir, module_mfas, reachable_modules, module_info_plt) do
    module = module_def_ir.module.value
    module_mfas = MapSet.new(module_mfas)

    function_defs =
      module_def_ir.body.expressions
      |> Enum.filter(fn
        %IR.FunctionDefinition{name: function, arity: arity} ->
          MapSet.member?(module_mfas, {module, function, arity})

        _fallback ->
          false
      end)
      |> maybe_prune_protocol_dispatcher_function_defs(module, reachable_modules, module_info_plt)

    %IR.ModuleDefinition{
      module: module_def_ir.module,
      body: %IR.Block{expressions: function_defs}
    }
  end

  @doc """
  Whether the bundle the given bundle info describes can still be served from the given static dir:
  it was written there, and both the bundle and its source map are on disk. A build dir can lose
  bundles to another build env sharing the static dir, and the info names one static dir, so reusing
  it for another would put a digest into that dir's page digest PLT whose file lives elsewhere.
  """
  @spec usable_bundle?(map, T.file_path()) :: boolean
  def usable_bundle?(bundle_info, static_dir) do
    Path.dirname(bundle_info.static_bundle_path) == static_dir and
      File.exists?(bundle_info.static_bundle_path) and
      File.exists?(bundle_info.static_source_map_path)
  end

  @doc """
  Raises a compilation error if any page module lacks a specified route or layout, or has a route that
  is not a string. The route and the layout come from the pages' entries in the given module info PLT;
  a page is asked only for what its entry does not hold (a route built at runtime, say).

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/validate_page_modules_2/README.md
  """
  @spec validate_page_modules(list(module), PLT.t()) :: :ok
  def validate_page_modules(page_modules, module_info_plt) do
    Enum.each(page_modules, fn page_module ->
      info = PLT.get!(module_info_plt, page_module)
      validate_page_route(page_module, info.route)
      validate_page_layout(page_module, info.layout_module)
    end)
  end

  @doc """
  Raises a compilation error if a template uses a component without one of its required props.

  Only usages the compiler can decide are checked. A usage carrying a `...{expr}` spread is skipped,
  since any prop could be in the spread, and so is a prop declared with `:from_context`, which is
  never written at the usage. Those cases, along with dynamic tags, are left to the renderers.

  Modules missing from the IR PLT are skipped - a module without a BEAM source has no IR to walk.

  Returns, for each given module, the modules its template uses as components, whether or not they
  are components: with its own template, all its result depends on (see
  `list_templatables_to_validate/3`). A skipped module uses none.
  """
  @spec validate_prop_usages(list(module), PLT.t()) :: %{module => MapSet.t(module)}
  def validate_prop_usages(modules, ir_plt) do
    Map.new(modules, fn module ->
      usages =
        case PLT.get(ir_plt, module) do
          {:ok, ir} -> validate_module_prop_usages(module, ir)
          :error -> []
        end

      used_modules =
        MapSet.new(usages, fn {component_module, _prop_entries, _has_spread?} ->
          component_module
        end)

      {module, used_modules}
    end)
  end

  # An entry name, a module, tells apart the entries bundled under one bundle name (the pages), so
  # it goes into the file name, without its Elixir prefix like the entry file name; a bundle name
  # with a single entry (the runtime) has none.
  defp bundle_output_name(bundle_name, nil), do: bundle_name

  defp bundle_output_name(bundle_name, entry_name) do
    "#{bundle_name}-#{Reflection.module_name(entry_name)}"
  end

  # A component node is a 4-element tuple whose first element is the :component atom and whose
  # second is the component module, already resolved by the time the template AST becomes IR. A
  # dynamic tag carries :dynamic_tag instead and never matches, which is what leaves it out.
  # Props and children are walked as well - props hold expressions, children hold nested usages.
  defp collect_component_usages(
         %IR.TupleType{
           data: [
             %IR.AtomType{value: :component},
             %IR.AtomType{value: component_module},
             %IR.ListType{data: props},
             %IR.ListType{data: children}
           ]
         },
         acc
       ) do
    usage = {component_module, prop_entries(props), has_spread?(props)}

    collect_component_usages(children, collect_component_usages(props, [usage | acc]))
  end

  defp collect_component_usages(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &collect_component_usages/2)
  end

  # Structs are maps too, so this walks every IR node's fields without naming any of them.
  defp collect_component_usages(map, acc) when is_map(map) do
    map
    |> Map.to_list()
    |> Enum.reduce(acc, fn {key, value}, key_acc ->
      collect_component_usages(value, collect_component_usages(key, key_acc))
    end)
  end

  defp collect_component_usages(tuple, acc) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.reduce(acc, &collect_component_usages/2)
  end

  defp collect_component_usages(_ir, acc), do: acc

  defp component_usage_error!(component_module, name, module) do
    raise Hologram.CompileError,
      message:
        "component #{Reflection.module_name(component_module)} is missing required prop " <>
          ~s/"#{name}" in #{Reflection.module_name(module)}'s template/
  end

  defp component_value_error!(component_module, {name, value, values}, module) do
    raise Hologram.CompileError,
      message:
        ~s/prop "#{name}" of component #{Reflection.module_name(component_module)} must be one of / <>
          "#{inspect(values)}, got: #{inspect(value)}, " <>
          "in #{Reflection.module_name(module)}'s template"
  end

  defp create_entry_file(js, entry_name, tmp_dir) do
    entry_file_path = Path.join(tmp_dir, "#{entry_name}.entry.js")
    File.write!(entry_file_path, js)

    entry_file_path
  end

  # A dump written by an older Hologram can hold entries without the keys added since. Fetched
  # dependencies lose their build dir, dumps included, when Mix recompiles them, but a path
  # dependency or the project itself keeps it, so the entry is checked rather than trusted.
  defp current_module_info?(info) do
    Enum.all?(Reflection.beam_info_keys(), &Map.has_key?(info, &1))
  end

  defp digest_js_input(path) do
    case File.read(path) do
      {:ok, content} -> {:digest, :erlang.phash2(content)}
      {:error, _reason} -> :missing
    end
  end

  defp edited_module?(old_infos, module, digest) do
    match?(%{digest: old_digest} when old_digest != digest, old_infos[module])
  end

  # The module IR is read once here however many functions are missing. A later entry file that
  # needs a function this one did not reads it again, so a module is copied out of the IR PLT
  # once per entry file that finds one of its functions missing, not once per compile. A function
  # the module does not define is stored as nil.
  defp encode_missing_module_functions(fun_arities, module, ir_plt, encode_plt, context) do
    module_name = Reflection.module_name(module)

    # Read outside the rescue below, so a module absent from the IR PLT raises the KeyError it
    # always did rather than being reported as an encoding failure.
    funs =
      ir_plt
      |> PLT.get!(module)
      |> IR.aggregate_module_funs()
      |> Map.new()

    try do
      Enum.each(fun_arities, fn {function, arity} = key ->
        case funs do
          %{^key => {visibility, clauses}} ->
            js =
              Encoder.encode_elixir_function(
                module_name,
                function,
                arity,
                visibility,
                clauses,
                context
              )

            PLT.put(encode_plt, {module, function, arity}, js)

          # Remembered as defining nothing, so later entry files that reach it do not read the
          # module again.
          _no_definition ->
            PLT.put(encode_plt, {module, function, arity}, nil)
        end
      end)
    rescue
      error ->
        message =
          StringUtils.normalize_newlines("""
          can't encode #{module_name} module definition
          #{Exception.message(error)}\
          """)

        reraise RuntimeError, [message: message], __STACKTRACE__
    end
  end

  defp encode_module_function_defs(fun_arities, module, ir_plt, encode_plt, context) do
    missing = Enum.reject(fun_arities, &function_encoded?(encode_plt, module, &1))

    if missing != [] do
      encode_missing_module_functions(missing, module, ir_plt, encode_plt, context)
    end

    Enum.flat_map(fun_arities, fn {function, arity} ->
      case PLT.get(encode_plt, {module, function, arity}) do
        # A reachable MFA with no definition in the module IR renders nothing, which is what
        # prune_module_def/4 does with it.
        {:ok, nil} ->
          []

        {:ok, js} ->
          [js]

        # Unreachable once the missing functions are encoded; kept so an entry without a value
        # renders nothing.
        :error ->
          []
      end
    end)
  end

  defp extract_erlang_function_js(file_path, function, arity) do
    key = "#{function}/#{arity}"
    start_marker = "// Start #{key}"
    end_marker = "// End #{key}"

    # Matches: start_marker, optional // comment lines, "key": <captured body>, end_marker
    regex =
      ~r/#{Regex.escape(start_marker)}\s+(?:\/\/[^\n]*\s+)*"#{Regex.escape(key)}":\s+(.+),\s+#{Regex.escape(end_marker)}/s

    file_contents = File.read!(file_path)

    case Regex.run(regex, file_contents) do
      [_full_capture, js] -> js
      nil -> nil
    end
  end

  # The IR PLT answers for every module it holds, so a module the compiler knows never costs a
  # code path lookup here, however many MFAs of it the list has.
  defp filter_elixir_mfas(mfas, ir_plt) do
    Enum.filter(mfas, fn {module, _function, _arity} ->
      Reflection.elixir_module?(module, ir_plt)
    end)
  end

  defp filter_erlang_mfas(mfas, ir_plt) do
    Enum.filter(mfas, fn {module, _function, _arity} ->
      Reflection.erlang_module?(module, ir_plt)
    end)
  end

  defp fingerprint_js_input(path, started_at) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} when is_integer(started_at) and mtime >= started_at ->
        :fresh

      {:ok, %File.Stat{mtime: mtime, size: size}} ->
        if "node_modules" in Path.split(path) do
          {:stat, mtime, size}
        else
          digest_js_input(path)
        end

      {:error, _reason} ->
        :missing
    end
  end

  defp function_encoded?(encode_plt, module, {function, arity}) do
    PLT.member?(encode_plt, {module, function, arity})
  end

  defp get_module_info(plt, module) do
    case PLT.get(plt, module) do
      {:ok, info} -> info
      :error -> nil
    end
  end

  defp get_package_json_digest(assets_dir) do
    assets_dir
    |> Path.join("package.json")
    |> File.read!()
    |> CryptographicUtils.digest(:sha256, :binary)
  end

  defp has_spread?(props) do
    Enum.any?(props, &match?(%IR.TupleType{data: [%IR.AtomType{value: :spread}, _expr]}, &1))
  end

  # Only props whose value is known without running anything are judged. The comparison needs no
  # type guard: nothing casts a prop to its declared type, so a text value stays the string it was
  # written as, and the renderers compare it against values: exactly the same way.
  defp invalid_prop_values(component_module, prop_entries) do
    values_by_name =
      component_module.__props__()
      |> Enum.flat_map(fn {name, _type, opts} ->
        if opts[:values], do: [{to_string(name), opts[:values]}], else: []
      end)
      |> Map.new()

    Enum.flat_map(prop_entries, fn
      {name, {:ok, value}} ->
        values = values_by_name[name]

        if values && value not in values, do: [{name, value, values}], else: []

      {_name, :unknown} ->
        []
    end)
  end

  defp included_protocol_implementations(reachable_modules, protocol, module_info_plt) do
    reachable_modules
    |> Enum.filter(&(Reflection.protocol_implementation(&1, module_info_plt) == protocol))
    |> MapSet.new()
  end

  # The catch-all clause returns nil and every included implementation ships in the bundle, so
  # only a clause naming another module needs the module info PLT to say whether it is an
  # implementation of this protocol (dropped) or something else (kept).
  defp keep_protocol_dispatcher_function_def?(
         %IR.FunctionDefinition{name: function, arity: 1, clause: clause},
         protocol,
         included_impls,
         module_info_plt
       )
       when function in [:impl_for, :struct_impl_for] do
    case clause do
      %IR.FunctionClause{body: %IR.Block{expressions: [%IR.AtomType{value: value}]}} ->
        is_nil(value) or MapSet.member?(included_impls, value) or
          Reflection.protocol_implementation(value, module_info_plt) != protocol

      _clause ->
        true
    end
  end

  defp keep_protocol_dispatcher_function_def?(
         _function_def,
         _protocol,
         _included_impls,
         _module_info_plt
       ),
       do: true

  # nil when the page must be rebuilt, its kept state otherwise.
  defp keepable_page_state(
         pages_plt,
         page_module,
         reaching_modules,
         js_fingerprints,
         pending_pages,
         static_dir
       ) do
    with false <- MapSet.member?(pending_pages, page_module),
         {:ok, page_state} <- PLT.get(pages_plt, page_module),
         true <- MapSet.disjoint?(page_state.modules, reaching_modules),
         false <- js_inputs_changed?(page_state.bundle_info.js_inputs, js_fingerprints),
         true <- usable_bundle?(page_state.bundle_info, static_dir) do
      page_state
    else
      _fallback -> nil
    end
  end

  # The files esbuild read for a bundle, as its metafile lists them relative to the working dir,
  # with their fingerprints taken against the time esbuild started (see fingerprint_js_inputs/2).
  # The entry file (under the tmp dir), Hologram's own sources (under the js dir) and the packages
  # they use are left out: the bundle inputs cover those for every bundle at once (see
  # build_bundle_inputs/2). esbuild resolves a package from the importing file's dir upwards, so
  # Hologram's sources take theirs from the node_modules next to the js dir; the node_modules path
  # opt names the same dir in an app, and is left out too.
  defp list_bundle_js_inputs(metafile_path, started_at, opts) do
    cwd = File.cwd!()

    hologram_node_modules_dir =
      if opts[:js_dir] do
        opts[:js_dir]
        |> Path.dirname()
        |> Path.join("node_modules")
      end

    left_out_dirs =
      [opts[:tmp_dir], opts[:js_dir], hologram_node_modules_dir, opts[:node_modules_path]]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Path.expand/1)

    metafile_path
    |> File.read!()
    |> JSON.decode!()
    |> Map.fetch!("inputs")
    |> Map.keys()
    |> Enum.map(&Path.expand(&1, cwd))
    |> Enum.reject(fn path -> Enum.any?(left_out_dirs, &(Path.relative_to(path, &1) != path)) end)
    |> fingerprint_js_inputs(started_at)
  end

  # Hologram's own modules that the module info PLT holds, with their digests, sorted: the modules of
  # the :hologram app whose source is in Hologram's lib dir, the dir the Hologram module itself was
  # compiled from. Hologram's own tests compile their fixtures into the :hologram app too, and an
  # edit of a fixture is an edit of an app module, not of Hologram.
  defp list_hologram_module_digests(module_info_plt) do
    Application.ensure_loaded(:hologram)

    lib_dir =
      :compile
      |> Hologram.module_info()
      |> Keyword.fetch!(:source)
      |> to_string()
      |> Path.dirname()

    digests =
      for module <- Application.spec(:hologram, :modules),
          {:ok, %{digest: digest, source_path: source_path}} <- [PLT.get(module_info_plt, module)],
          is_binary(source_path),
          Path.relative_to(source_path, lib_dir) != source_path do
        {module, digest}
      end

    Enum.sort(digests)
  end

  # Every regular file under the given dir, as its path relative to the dir with its mtime and size,
  # sorted.
  defp list_js_sources(js_dir) do
    js_dir
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      case File.stat!(path, time: :posix) do
        %File.Stat{type: :regular, mtime: mtime, size: size} ->
          [{Path.relative_to(path, js_dir), mtime, size}]

        _directory ->
          []
      end
    end)
    |> Enum.sort()
  end

  # Filtered in the table, so no info is copied out of it.
  defp list_modules_where(module_info_plt, flag) do
    module_info_plt
    |> PLT.keys(%{flag => true})
    |> Enum.sort()
  end

  # The modules of the given kind among the results of patch_module_info_plt_entry!/5, sorted.
  defp list_results(results, kind) do
    results
    |> Enum.flat_map(fn
      {^kind, module} -> [module]
      _other -> []
    end)
    |> Enum.sort()
  end

  defp maybe_ensure_bundle_within_size_limit!(entry_name, bundle_path) do
    max_bundle_size = Application.get_env(:hologram, :max_bundle_size)

    if max_bundle_size do
      bundle_size = File.stat!(bundle_path).size

      if bundle_size > max_bundle_size do
        raise RuntimeError,
          message: """
          Generated JavaScript bundle '#{entry_name}' is #{bundle_size} bytes, which exceeds the configured maximum of #{max_bundle_size} bytes.

          This limit acts as an early warning system to surface abnormally large bundles before they reach your app (e.g., accidentally pulling in too many modules or dependencies).

          You can change this limit by setting the [:hologram, :max_bundle_size] config value (in bytes). For example:

              config :hologram, max_bundle_size: 2 * 1024 * 1024\
          """
      end
    end
  end

  # Consolidated protocol dispatchers list every loaded implementation. Keep only
  # clauses for implementations that ship in the same bundle, so dispatch on other
  # types falls through to the catch-all clause and raises Protocol.UndefinedError.
  defp maybe_prune_protocol_dispatcher_function_defs(
         function_defs,
         module,
         reachable_modules,
         module_info_plt
       ) do
    if Reflection.protocol?(module, module_info_plt) do
      included_impls =
        included_protocol_implementations(reachable_modules, module, module_info_plt)

      Enum.filter(
        function_defs,
        &keep_protocol_dispatcher_function_def?(&1, module, included_impls, module_info_plt)
      )
    else
      function_defs
    end
  end

  # Any literal is resolved, composites included, as long as every part of it is one too - a single
  # expression anywhere inside makes the whole value unknowable until it runs. Pids, ports and
  # references can't be written in a template at all (they only come from calls, which aren't
  # literals), so the node types for them are not reachable here.
  defp literal_value(%IR.AtomType{value: value}), do: {:ok, value}
  defp literal_value(%IR.FloatType{value: value}), do: {:ok, value}
  defp literal_value(%IR.IntegerType{value: value}), do: {:ok, value}
  defp literal_value(%IR.StringType{value: value}), do: {:ok, value}

  defp literal_value(%IR.ListType{data: data}), do: literal_values(data)

  defp literal_value(%IR.TupleType{data: data}) do
    case literal_values(data) do
      {:ok, items} -> {:ok, List.to_tuple(items)}
      :unknown -> :unknown
    end
  end

  defp literal_value(%IR.MapType{data: data}) do
    {key_irs, value_irs} = Enum.unzip(data)

    with {:ok, keys} <- literal_values(key_irs),
         {:ok, values} <- literal_values(value_irs) do
      map =
        keys
        |> Enum.zip(values)
        |> Map.new()

      {:ok, map}
    end
  end

  defp literal_value(_ir), do: :unknown

  # One unresolvable part makes the whole composite unresolvable - a list holding an expression has
  # no value until that expression runs.
  defp literal_values(irs) do
    result =
      Enum.reduce_while(irs, {:ok, []}, fn ir, {:ok, acc} ->
        case literal_value(ir) do
          {:ok, value} -> {:cont, {:ok, [value | acc]}}
          :unknown -> {:halt, :unknown}
        end
      end)

    case result do
      {:ok, reversed_values} -> {:ok, Enum.reverse(reversed_values)}
      :unknown -> :unknown
    end
  end

  # A prop sourced from context is never written at the usage, so its absence there says nothing -
  # only the renderers can tell whether the context supplied it.
  defp missing_required_props(component_module, prop_names) do
    component_module.__props__()
    |> Enum.filter(fn {name, _type, opts} ->
      opts[:required] && !opts[:from_context] && to_string(name) not in prop_names
    end)
    |> Enum.map(fn {name, _type, _opts} -> name end)
  end

  # The application Reflection.list_module_applications/0 names for the module: the first loaded
  # application, in the same order, whose modules list it.
  defp module_application(module) do
    Enum.find_value(Application.loaded_applications(), fn {app, _description, _version} ->
      if module in List.wrap(Application.spec(app, :modules)), do: app
    end)
  end

  # A compiled module is read. The entry of any other module is left as it is, unless it is a
  # protocol's, whose consolidated beam a new implementation rewrites without a compile; that one,
  # and a beam with no entry, is checked against its mtime and size first.
  defp patch_module_info_plt_entry!(plt, module, beam_path, dumped_at, compiled_modules) do
    old_info = get_module_info(plt, module)

    cond do
      MapSet.member?(compiled_modules, module) ->
        put_compared_module_info(plt, module, old_info, Reflection.beam_info(beam_path))

      match?(%{protocol?: false}, old_info) ->
        :kept

      true ->
        new_info =
          reusable_module_info(module, beam_path, plt, dumped_at) ||
            Reflection.beam_info(beam_path)

        put_compared_module_info(plt, module, old_info, new_info)
    end
  end

  # A module that left the listing without its beam being deleted, as the full scan would see it. A
  # path the VM still names for a module whose file is gone, or for one compiled in memory, has
  # nothing to read, so the module loses its entry, as a deleted one.
  defp patch_vanished_module_info!(plt, module, dumped_at, umbrella?) do
    beam_source = resolve_beam_source(module, umbrella?)
    old_info = get_module_info(plt, module)

    new_info =
      if beam_source && (is_binary(beam_source) or File.regular?(beam_source)) do
        reusable_module_info(module, beam_source, plt, dumped_at) ||
          Reflection.beam_info(beam_source)
      end

    put_compared_module_info(plt, module, old_info, new_info)
  end

  # $-prefixed entries are the framework's own ($key, event bindings), never something the author
  # declared with prop/3, so they are not props as far as a usage is concerned.
  defp prop_entries(props) do
    props
    |> Enum.flat_map(fn
      %IR.TupleType{data: [%IR.StringType{value: name}, %IR.ListType{data: value_dom}]} ->
        [{name, static_prop_value(value_dom)}]

      _entry ->
        []
    end)
    |> Enum.reject(fn {name, _value} -> String.starts_with?(name, "$") end)
  end

  # Mirrors evaluate_prop_value/1 in the renderer: a lone expression yields its term as it is, and
  # anything else is rendered to a string. So a value is known here only when the expression is a
  # literal, or when the value is text with nothing interpolated into it.
  defp static_prop_value([
         %IR.TupleType{data: [%IR.AtomType{value: :expression}, %IR.TupleType{data: [expr]}]}
       ]) do
    literal_value(expr)
  end

  defp static_prop_value([_first | _rest] = value_dom) do
    if Enum.all?(
         value_dom,
         &match?(%IR.TupleType{data: [%IR.AtomType{value: :text}, %IR.StringType{}]}, &1)
       ) do
      {:ok,
       Enum.map_join(value_dom, "", fn %IR.TupleType{data: [_tag, %IR.StringType{value: str}]} ->
         str
       end)}
    else
      :unknown
    end
  end

  defp static_prop_value(_value_dom), do: :unknown

  # Read gives nil: not an Elixir module.
  # Puts the new entry in place of the old one and says what that was: an addition, an edit (another
  # digest), a touch (the same digest, another mtime or size), a removal (a beam that no longer reads
  # as an Elixir module, or none), or nothing.
  defp put_compared_module_info(_plt, _module, nil, nil), do: :kept

  defp put_compared_module_info(plt, module, _old_info, nil) do
    PLT.delete(plt, module)
    {:removed, module}
  end

  defp put_compared_module_info(_plt, _module, info, info), do: :kept

  defp put_compared_module_info(plt, module, old_info, new_info) do
    PLT.put(plt, module, new_info)

    cond do
      old_info == nil -> {:added, module}
      old_info.digest != new_info.digest -> {:edited, module}
      true -> {:touched, module}
    end
  end

  defp put_module_info(new_plt, module, info) do
    if info, do: PLT.put(new_plt, module, info)
  end

  # Not reusable: read it.
  defp put_module_info_plt_entry!(new_plt, module, beam_source, old_plt, dumped_at) do
    info =
      reusable_module_info(module, beam_source, old_plt, dumped_at) ||
        Reflection.beam_info(beam_source)

    put_module_info(new_plt, module, info)
  end

  # The kept pages whose MFAs moved, and the ones whose MFAs are unchanged, with their states. A
  # page's MFAs as its bundle was built from them are read from the page MFAs PLT. A page with no
  # list there counts as moved: its state was loaded from the compile state dump, which does not hold
  # the lists (see Hologram.Compiler.Cache.dump_compile_state/2).
  defp relist_kept_pages(kept_pages, call_graph, page_mfas_plt, gate) do
    mfas_by_kept_page =
      kept_pages
      |> Enum.map(fn {page_module, _page_state} -> page_module end)
      |> list_mfas_by_page(call_graph, gate: gate)
      |> Map.new()

    {changed_pages, unchanged_pages} =
      Enum.split_with(kept_pages, fn {page_module, _page_state} ->
        PLT.get(page_mfas_plt, page_module) != {:ok, mfas_by_kept_page[page_module]}
      end)

    moved_pages = Enum.map(changed_pages, fn {page_module, _page_state} -> page_module end)

    {moved_pages, unchanged_pages}
  end

  # TODO: Drop the umbrella? param and resolve the beam path with :code.which/1
  # when resolve_beam_source/2 goes (see the removal note there).
  defp rebuild_module_info_plt_entry!(module, old_plt, dumped_at, new_plt, umbrella?) do
    # No beam: not a module of this project.
    if beam_source = resolve_beam_source(module, umbrella?) do
      put_module_info_plt_entry!(new_plt, module, beam_source, old_plt, dumped_at)
    end
  end

  # Travels with the per-module metadata, which is emitted under the same
  # setting - a bundle built without client stacktraces names no application
  # and no version anywhere.
  defp render_app_versions(app_versions) do
    if Hologram.client_stacktraces?() do
      app_versions
      |> Enum.map_join(", ", fn {app, vsn} -> ~s/"#{app}": "#{vsn}"/ end)
      |> then(&"{#{&1}}")
    else
      "{}"
    end
  end

  defp render_block(str) do
    str = String.trim(str)

    if str != "" do
      "\n\n" <> str
    else
      ""
    end
  end

  # Functions are listed by module, then function name, then arity. The module order is the
  # sort below; the order within a module comes from IR.aggregate_module_funs/1 on the protocol
  # path and from the sort in render_module_function_defs/7 on the cached one.
  defp render_elixir_function_defs(mfas, ir_plt, encode_plt, async_mfas, module_info_plt) do
    mfas_by_module =
      mfas
      |> filter_elixir_mfas(ir_plt)
      |> group_mfas_by_module()
      |> Enum.sort()

    reachable_modules = MapSet.new(mfas_by_module, fn {module, _module_mfas} -> module end)

    mfas_by_module
    |> TaskUtils.map_concurrently(fn {module, module_mfas} ->
      render_module_function_defs(
        module,
        module_mfas,
        reachable_modules,
        ir_plt,
        encode_plt,
        async_mfas,
        module_info_plt
      )
    end)
    |> Enum.join("\n\n")
  end

  # A manually ported function's clauses aren't encoded, so its raise sites have
  # no attempted clauses to report. Their heads are registered separately, from
  # the IR of the Elixir function the port stands in for.
  defp render_manually_ported_clause_heads(ir_plt) do
    CallGraph.manually_ported_elixir_mfas()
    |> Enum.map(fn {module, function, _arity} -> {module, function} end)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.flat_map(fn {module, function} ->
      render_manually_ported_clause_heads(ir_plt, module, function)
    end)
    |> Enum.join("\n")
  end

  # A raise reports the arity the function was defined with, which a default
  # argument makes differ from the arity the port replaces - Task.await/1 is
  # ported, but its clause is await/2 - so every arity is registered.
  defp render_manually_ported_clause_heads(ir_plt, module, function) do
    module_name = Reflection.module_name(module)

    case PLT.get(ir_plt, module) do
      {:ok, module_def} ->
        module_def
        |> IR.aggregate_module_funs()
        |> Enum.filter(fn {{name, _arity}, _fun} -> name == function end)
        |> Enum.sort()
        |> Enum.map(fn {{name, arity}, {visibility, clauses}} ->
          Encoder.encode_elixir_function_clause_heads(
            module_name,
            name,
            arity,
            visibility,
            clauses,
            %Context{ir_plt: ir_plt, module: module}
          )
        end)

      :error ->
        []
    end
  end

  # A protocol's dispatcher functions are selected against the whole reachable set, in
  # maybe_prune_protocol_dispatcher_function_defs/4, so their JavaScript depends on the entry
  # file being built and cannot be keyed by MFA alone. Every other module's functions encode
  # the same wherever they are reached from, so each is encoded once per compile in the common
  # case, and never differently. The module info PLT answers whether a module is a protocol and
  # which protocol a module implements, so no module is asked, or loaded, once per entry file.
  defp render_module_function_defs(
         module,
         module_mfas,
         reachable_modules,
         ir_plt,
         encode_plt,
         async_mfas,
         module_info_plt
       ) do
    context = %Context{async_mfas: async_mfas, ir_plt: ir_plt, module: module}

    if Reflection.protocol?(module, module_info_plt) do
      ir_plt
      |> PLT.get!(module)
      |> prune_module_def(module_mfas, reachable_modules, module_info_plt)
      |> Encoder.encode_ir(context)
    else
      module_mfas
      |> Enum.map(fn {_module, function, arity} -> {function, arity} end)
      |> Enum.sort()
      |> encode_module_function_defs(module, ir_plt, encode_plt, context)
      |> Enum.join("\n\n")
    end
  end

  defp render_module_metadata_registration(mfas, ir_plt, module_metadata) do
    mfas
    |> filter_elixir_mfas(ir_plt)
    |> Enum.map(fn {module, _function, _arity} -> module end)
    |> Enum.uniq()
    |> Encoder.encode_module_metadata_registration(module_metadata)
  end

  defp render_erlang_function_defs(mfas, ir_plt, erlang_js_dir) do
    mfas
    |> filter_erlang_mfas(ir_plt)
    |> TaskUtils.map_concurrently(fn {module, function, arity} ->
      Encoder.encode_erlang_function(module, function, arity, erlang_js_dir)
    end)
    |> Enum.join("\n\n")
  end

  defp render_js_bindings_registration_call(bindings) when bindings == %{}, do: ""

  defp render_js_bindings_registration_call(bindings) do
    modules_arg =
      bindings
      |> Enum.sort()
      |> Enum.map_join(", ", fn {module, module_bindings} ->
        module_name = Reflection.module_name(module)

        entries =
          module_bindings
          |> Enum.sort()
          |> Enum.map_join(", ", fn {as, alias} -> ~s'"#{as}": #{alias}' end)

        ~s'"#{module_name}": {#{entries}}'
      end)

    ~s'Interpreter.registerJsBindings({#{modules_arg}});'
  end

  defp render_js_import_statements(imports) do
    Enum.map_join(imports, "\n", fn %{from: from, export: export, alias: alias} ->
      ~s'import { #{export} as #{alias} } from "#{from}";'
    end)
  end

  # In umbrella projects a module can stay loaded from a consolidated protocol
  # beam that Phoenix's code reloader has purged: the reloader compiles with
  # --purge-consolidation-path-if-stale, which deletes the umbrella root
  # consolidated dir while :code.which/1 keeps pointing into it. The beam source
  # is therefore resolved through Reflection.beam_source/1, which falls back to
  # the module's object code. Single-app projects never hit that state, so they
  # resolve through a plain :code.which/1 lookup with no per-module overhead.
  # Note that this is NOT fixed by the Phoenix > 1.8.9 code reloader rework
  # (phoenixframework/phoenix#6753) - the purge flag is still passed after it.
  # TODO: Remove the umbrella branch once upstream stops leaving loaded modules
  # pointing at purged consolidated beams. That means this function,
  # Reflection.beam_source/1 and Reflection.umbrella?/0 (if nothing else uses
  # them by then), plus unwinding the umbrella? flag threaded through
  # build_ir_plt/1, build_module_info_plt!/3 and
  # rebuild_module_info_plt_entry!/5 - their bodies go back to resolving the
  # beam path with :code.which/1 directly.
  defp resolve_beam_source(module, true), do: Reflection.beam_source(module)

  defp resolve_beam_source(module, false) do
    beam_path = :code.which(module)

    if beam_path != :non_existing do
      beam_path
    end
  end

  # The previous entry is trusted only when the beam file looks untouched (same mtime and size) and was
  # written at least a second before the previous dump: mtimes have whole-second resolution, so a beam
  # rewritten during the dump's own second could match on both and still differ. A beam that came as a
  # binary (see resolve_beam_source/2) has no file to stat and is always read, as is everything when
  # there is no previous dump.
  defp reusable_module_info(module, beam_path, old_plt, dumped_at)
       when is_list(beam_path) and is_integer(dumped_at) do
    with {:ok, %{mtime: mtime, size: size} = info} when is_integer(mtime) <-
           PLT.get(old_plt, module),
         {:ok, %File.Stat{mtime: ^mtime, size: ^size}} when mtime <= dumped_at - 1 <-
           File.stat(beam_path, time: :posix),
         true <- current_module_info?(info) do
      info
    else
      _fallback -> nil
    end
  end

  defp reusable_module_info(_module, _beam_source, _old_plt, _dumped_at), do: nil

  defp validate_module_prop_usages(module, ir) do
    usages =
      ir
      |> template_ir()
      |> list_component_usages()

    Enum.each(usages, &validate_prop_usage(&1, module))

    usages
  end

  # Only the template's own DOM is validated. A component node is an ordinary 4-tuple, so code
  # elsewhere in the module - a helper building DOM by hand, a fixture - can hold one without any
  # template rendering it, and validating those would fail a build over a component nobody uses.
  defp template_ir(%IR.ModuleDefinition{body: %IR.Block{expressions: expressions}}) do
    Enum.find(expressions, &match?(%IR.FunctionDefinition{name: :template, arity: 0}, &1))
  end

  defp template_ir(_ir), do: nil

  # A spread decides only whether a prop is present, so it blocks the required check and nothing
  # else. A value written at the usage is judged either way: being overridden by a later spread
  # doesn't make an invalid literal valid, it just makes it dead as well as wrong.
  defp validate_page_layout(page_module, nil) do
    if !Reflection.has_function?(page_module, :__layout_module__, 0) do
      module_name = Reflection.module_name(page_module)

      raise Hologram.CompileError,
        message:
          "page '#{module_name}' doesn't have a layout module specified (use the layout/1 macro to fix it)"
    end
  end

  defp validate_page_layout(_page_module, _layout_module), do: :ok

  # A route the module info PLT does not hold is either missing or built at runtime; only the second
  # can be asked from the page.
  defp validate_page_route(page_module, nil) do
    if !Reflection.has_function?(page_module, :__route__, 0) do
      module_name = Reflection.module_name(page_module)

      raise Hologram.CompileError,
        message:
          "page '#{module_name}' doesn't have a route specified (use the route/1 macro to fix it)"
    end

    validate_page_route_type(page_module, page_module.__route__())
  end

  defp validate_page_route(page_module, route), do: validate_page_route_type(page_module, route)

  defp validate_page_route_type(_page_module, route) when is_binary(route), do: :ok

  defp validate_page_route_type(page_module, route) do
    module_name = Reflection.module_name(page_module)

    raise Hologram.CompileError,
      message:
        "page '#{module_name}' has a route that is not a string: #{inspect(route)} (pass a string to the route/1 macro to fix it)"
  end

  defp validate_prop_usage({component_module, prop_entries, has_spread?}, module) do
    if Reflection.has_function?(component_module, :__props__, 0) do
      validate_required_props(component_module, prop_entries, has_spread?, module)

      # Matched rather than iterated: both error functions only raise, so a capture of one would be
      # an anonymous function with no local return. Reporting the first violation is what iterating
      # did anyway - the raise ended it.
      case invalid_prop_values(component_module, prop_entries) do
        [] -> :ok
        [violation | _rest] -> component_value_error!(component_module, violation, module)
      end
    end
  end

  # A spread could supply any prop, so nothing can be proven missing at a usage carrying one.
  defp validate_required_props(_component_module, _prop_entries, true, _module), do: :ok

  defp validate_required_props(component_module, prop_entries, false, module) do
    prop_names = Enum.map(prop_entries, fn {name, _value} -> name end)

    case missing_required_props(component_module, prop_names) do
      [] -> :ok
      [name | _rest] -> component_usage_error!(component_module, name, module)
    end
  end
end
