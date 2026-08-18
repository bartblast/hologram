defmodule Hologram.Compiler do
  @moduledoc false

  alias Hologram.Commons.CryptographicUtils
  alias Hologram.Commons.MapUtils
  alias Hologram.Commons.PathUtils
  alias Hologram.Commons.PLT
  alias Hologram.Commons.SystemUtils
  alias Hologram.Commons.TaskUtils
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.QueryExtractor
  alias Hologram.DB.Codec
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Query.Registry
  alias Hologram.Query.Window
  alias Hologram.Reflection
  alias Hologram.Sync.Frame

  @doc """
  Aggregates JS imports from all Elixir modules referenced by the given MFAs.
  Returns a map with:
  - `:imports` — unique imports with generated `$1`, `$2`, ... aliases for JS import statements
  - `:bindings` — per-module map of user alias to generated alias for `__bindings__` on module proxies
  """
  @spec aggregate_js_imports(list(mfa)) :: %{
          imports: list(%{from: String.t(), export: String.t(), alias: String.t()}),
          bindings: %{module => %{String.t() => String.t()}}
        }
  def aggregate_js_imports(mfas) do
    modules_with_imports =
      mfas
      |> filter_elixir_mfas()
      |> Enum.map(fn {module, _function, _arity} -> module end)
      |> Enum.uniq()
      |> Enum.filter(
        &(Reflection.has_function?(&1, :__js_imports__, 0) and &1.__js_imports__() != [])
      )

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
    |> Enum.map(fn
      {module, _function, _arity} -> module
      module -> module
    end)
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
  Returns the ids of the windows each of the given pages downloads, keyed by page module and
  sorted.

  A page's windows are those of every component it can reach, not only the ones a given render
  mounts. A panel that opens on a click is reachable without being rendered, and its rows have to
  be on the client before the click rather than after it - which is the whole point of holding
  the rows a page may need rather than the ones it is showing.

  A page reaching no query at all has no windows, and answers with an empty list rather than
  being left out.
  """
  @spec build_page_windows(list(module), CallGraph.t()) :: %{module => list(String.t())}
  def build_page_windows(page_modules, call_graph) do
    graph = CallGraph.get_graph(call_graph)
    templatables = page_modules ++ Reflection.list_components()
    analysis = CallGraph.server_callback_analysis_by_templatable(graph, templatables)

    Map.new(page_modules, fn page_module ->
      {page_module, page_window_ids(page_module, call_graph, analysis)}
    end)
  end

  @doc """
  Builds the call graph of all modules in the project.
  """
  @spec build_call_graph :: CallGraph.t()
  def build_call_graph do
    build_call_graph(build_ir_plt())
  end

  @doc """
  Builds the call graph of all modules in the given IR PLT.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/build_call_graph_1/README.md
  """
  @spec build_call_graph(PLT.t()) :: CallGraph.t()
  def build_call_graph(ir_plt) do
    call_graph = CallGraph.start()

    ir_plt
    |> PLT.get_all()
    |> TaskUtils.async_many(fn {_module, ir} -> CallGraph.build(call_graph, ir) end)
    |> Task.await_many(:infinity)

    CallGraph.add_non_discoverable_edges(call_graph)
  end

  @doc """
  Builds IR persistent lookup table (PLT) of all modules in the project.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/build_ir_plt_1/README.md
  """
  @spec build_ir_plt(T.opts()) :: PLT.t()
  # credo:disable-for-lines:26 Credo.Check.Refactor.Nesting
  # The above Credo check is disabled because the function is optimised this way
  def build_ir_plt(opts \\ []) do
    ir_plt = PLT.start(opts)

    modules = Reflection.list_elixir_modules()

    # Processing modules in chunks of 2 improves performance by ~7%
    # (determined experimentally)
    chunk_size = 2

    # TODO: Remove this flag and call :code.which/1 directly below when
    # resolve_beam_source/2 goes (see the removal note there).
    umbrella? = Reflection.umbrella?()

    modules
    |> Enum.chunk_every(chunk_size)
    |> TaskUtils.async_many(fn module_chunk ->
      Enum.each(module_chunk, fn module ->
        beam_source = resolve_beam_source(module, umbrella?)

        if beam_source do
          ir = IR.for_module(module, beam_source)
          PLT.put(ir_plt, module, ir)
        end
      end)
    end)
    |> Task.await_many(:infinity)

    ir_plt
  end

  @doc """
  Builds a persistent lookup table (PLT) containing the BEAM defs digests for all the modules in the project.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/build_module_digest_plt!_1/README.md
  """
  @spec build_module_digest_plt!(T.opts()) :: PLT.t()
  def build_module_digest_plt!(opts \\ []) do
    module_digest_plt = PLT.start(opts)

    # TODO: Remove this flag and the argument it feeds to
    # rebuild_module_digest_plt_entry!/3 when resolve_beam_source/2 goes (see
    # the removal note there).
    umbrella? = Reflection.umbrella?()

    Reflection.list_elixir_modules()
    |> TaskUtils.async_many(&rebuild_module_digest_plt_entry!(&1, module_digest_plt, umbrella?))
    |> Task.await_many(:infinity)

    module_digest_plt
  end

  @doc """
  Builds page digest PLT, where the keys represent page modules,
  and the values are hex digests of their corresponding JavaScript bundles.
  """
  @spec build_page_digest_plt(list(map), T.opts()) :: {PLT.t(), T.file_path()}
  def build_page_digest_plt(bundle_info, opts) do
    page_digest_plt_items =
      bundle_info
      |> Enum.reject(fn %{entry_name: entry_name} -> entry_name == "runtime" end)
      |> Enum.reduce([], fn %{entry_name: page_module, digest: digest}, acc ->
        [{page_module, digest} | acc]
      end)

    page_digest_plt = PLT.start(items: page_digest_plt_items, supervisor: opts[:supervisor])

    page_digest_plt_dump_path =
      Path.join([opts[:build_dir], Reflection.page_digest_plt_dump_file_name()])

    {page_digest_plt, page_digest_plt_dump_path}
  end

  @doc """
  Builds the page windows PLT, where the keys are page modules and the values are the ids of the
  windows each page downloads, and returns it with the path to dump it at.
  """
  @spec build_page_windows_plt(%{module => list(String.t())}, T.opts()) ::
          {PLT.t(), T.file_path()}
  def build_page_windows_plt(page_windows, opts) do
    plt = PLT.start(items: Map.to_list(page_windows), supervisor: opts[:supervisor])
    dump_path = Path.join([opts[:build_dir], Reflection.page_windows_plt_dump_file_name()])

    {plt, dump_path}
  end

  @doc """
  Builds JavaScript code for the given Hologram page.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/build_page_js_6/README.md
  """
  @spec build_page_js(
          module,
          CallGraph.t(),
          PLT.t(),
          MapSet.t(mfa),
          %{module => CallGraph.server_callback_analysis()},
          T.file_path()
        ) :: String.t()
  def build_page_js(
        page_module,
        call_graph,
        ir_plt,
        async_mfas,
        server_callback_analysis_by_templatable,
        js_dir
      ) do
    mfas =
      CallGraph.list_page_mfas(call_graph, page_module, server_callback_analysis_by_templatable)

    %{imports: imports, bindings: bindings} = aggregate_js_imports(mfas)

    import_statements =
      imports
      |> Enum.map_join("\n", fn %{from: from, export: export, alias: alias} ->
        ~s'import { #{export} as #{alias} } from "#{from}";'
      end)
      |> render_block()

    js_bindings_registration_call =
      bindings
      |> render_js_bindings_registration_call()
      |> render_block()

    erlang_js_dir = Path.join(js_dir, "erlang")

    erlang_function_defs =
      mfas
      |> render_erlang_function_defs(erlang_js_dir)
      |> render_block()

    elixir_function_defs =
      mfas
      |> render_elixir_function_defs(ir_plt, async_mfas)
      |> render_block()

    module_metadata_registration =
      mfas
      |> render_module_metadata_registration()
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
  Builds Hologram runtime JavaScript source code.
  """
  @spec build_runtime_js(
          list(mfa),
          PLT.t(),
          MapSet.t(mfa),
          keyword(String.t()),
          %{entity_types: MapSet.t(module), ordered_string_pairs: MapSet.t({module, atom})},
          T.file_path()
        ) :: String.t()
  def build_runtime_js(
        runtime_mfas,
        ir_plt,
        async_mfas,
        app_versions,
        sync_constants,
        js_dir
      ) do
    erlang_function_defs =
      runtime_mfas
      |> render_erlang_function_defs(Path.join(js_dir, "erlang"))
      |> render_block()

    elixir_function_defs =
      runtime_mfas
      |> render_elixir_function_defs(ir_plt, async_mfas)
      |> render_block()

    module_metadata_registration =
      runtime_mfas
      |> render_module_metadata_registration()
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
    import Utils from "#{js_dir}/utils.mjs";

    const startTime = PerformanceTimer.start();

    globalThis.Hologram.config = #{render_client_config()};

    #{render_sync_constants(sync_constants)}

    ERTS.appVersions = #{render_app_versions(app_versions)};#{module_metadata_registration}#{erlang_function_defs}#{elixir_function_defs}#{manually_ported_clause_heads}

    document.addEventListener("hologram:pageScriptLoaded", () => Hologram.run());

    if (globalThis.Hologram.pageScriptLoaded) {
      document.dispatchEvent(new CustomEvent("hologram:pageScriptLoaded"));
    }

    console.debug("Hologram: runtime script executed in", PerformanceTimer.diff(startTime));\
    """
  end

  @doc """
  Bundles multiple entry files.
  Includes the source maps of the output files.
  The output files' and source maps' file names contain hex digest.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/bundle_2/README.md
  """
  @spec bundle(list({term, T.file_path(), String.t()}), T.opts()) :: list(map)
  def bundle(entry_files_info, opts) do
    entry_files_info
    |> TaskUtils.async_many(fn {entry_name, entry_file_path, bundle_name} ->
      bundle(entry_name, entry_file_path, bundle_name, opts)
    end)
    |> Task.await_many(:infinity)
  end

  @doc """
  Bundles the given entry file.
  Includes the source map of the output file.
  The output file and source map file names contain hex digest.
  """
  @spec bundle(term, T.file_path(), String.t(), T.opts()) :: map
  # sobelow_skip ["CI.System"]
  def bundle(entry_name, entry_file_path, bundle_name, opts) do
    output_bundle_path = Path.join(opts[:tmp_dir], "#{entry_name}.output.js")

    esbuild_cmd = [
      entry_file_path,
      "--bundle",
      "--log-level=warning",
      "--minify",
      "--outfile=#{output_bundle_path}",
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

    {_exit_msg, exit_status} =
      SystemUtils.cmd_cross_platform(opts[:esbuild_bin_path], esbuild_cmd, esbuild_opts)

    if exit_status != 0 do
      raise RuntimeError,
        message:
          "esbuild bundler failed for entry file: #{entry_file_path} (probably there were JavaScript syntax errors)"
    end

    maybe_ensure_bundle_within_size_limit!(entry_name, output_bundle_path)

    digest =
      output_bundle_path
      |> File.read!()
      |> CryptographicUtils.digest(:md5, :hex)

    static_bundle_path_with_digest = Path.join(opts[:static_dir], "#{bundle_name}-#{digest}.js")

    output_source_map_path = output_bundle_path <> ".map"
    static_source_map_path_with_digest = static_bundle_path_with_digest <> ".map"

    File.rename!(output_bundle_path, static_bundle_path_with_digest)
    File.rename!(output_source_map_path, static_source_map_path_with_digest)

    js_with_replaced_source_map_url =
      static_bundle_path_with_digest
      |> File.read!()
      |> String.replace(
        "//# sourceMappingURL=#{entry_name}.output.js.map",
        "//# sourceMappingURL=#{bundle_name}-#{digest}.js.map"
      )

    File.write!(static_bundle_path_with_digest, js_with_replaced_source_map_url)

    %{
      bundle_name: bundle_name,
      digest: digest,
      entry_name: entry_name,
      static_bundle_path: static_bundle_path_with_digest,
      static_source_map_path: static_source_map_path_with_digest
    }
  end

  @doc """
  Creates page bundle entry file.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/create_page_entry_files_5/README.md
  """
  @spec create_page_entry_files(list(module), CallGraph.t(), PLT.t(), MapSet.t(mfa), T.opts()) ::
          list({module, T.file_path()})
  def create_page_entry_files(page_modules, call_graph, ir_plt, async_mfas, opts) do
    graph = CallGraph.get_graph(call_graph)
    templatables = page_modules ++ Reflection.list_components()

    server_callback_analysis_by_templatable =
      CallGraph.server_callback_analysis_by_templatable(graph, templatables)

    page_modules
    |> TaskUtils.async_many(fn page_module ->
      entry_name = Reflection.module_name(page_module)

      entry_file_path =
        page_module
        |> build_page_js(
          call_graph,
          ir_plt,
          async_mfas,
          server_callback_analysis_by_templatable,
          opts[:js_dir]
        )
        |> create_entry_file(entry_name, opts[:tmp_dir])

      {page_module, entry_file_path}
    end)
    |> Task.await_many(:infinity)
  end

  @doc """
  Creates runtime bundle entry file.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/elixir/compiler/create_runtime_entry_file_5/README.md
  """
  @spec create_runtime_entry_file(
          list(mfa),
          PLT.t(),
          MapSet.t(mfa),
          keyword(String.t()),
          %{entity_types: MapSet.t(module), ordered_string_pairs: MapSet.t({module, atom})},
          T.opts()
        ) :: T.file_path()
  def create_runtime_entry_file(
        runtime_mfas,
        ir_plt,
        async_mfas,
        app_versions,
        sync_constants,
        opts
      ) do
    runtime_mfas
    |> build_runtime_js(ir_plt, async_mfas, app_versions, sync_constants, opts[:js_dir])
    |> create_entry_file("runtime", opts[:tmp_dir])
  end

  @doc """
  Compares two module digest PLTs and returns the added, removed, and edited modules lists.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/diff_module_digest_plts_2/README.md
  """
  @spec diff_module_digest_plts(PLT.t(), PLT.t()) :: %{
          added_modules: list(module),
          removed_modules: list(module),
          edited_modules: list(module)
        }
  def diff_module_digest_plts(old_plt, new_plt) do
    old_digests = PLT.get_all(old_plt)
    new_digests = PLT.get_all(new_plt)

    diff = MapUtils.diff(old_digests, new_digests)

    %{
      added_modules: Enum.map(diff.added, fn {module, _digest} -> module end),
      removed_modules: diff.removed,
      edited_modules: Enum.map(diff.edited, fn {module, _digest} -> module end)
    }
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
  Loads call graph from a dump file if the file exists or creates an empty call graph.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/maybe_load_call_graph_1/README.md
  """
  @spec maybe_load_call_graph(T.file_path(), T.opts()) :: {CallGraph.t(), String.t()}
  def maybe_load_call_graph(build_dir, opts \\ []) do
    call_graph = CallGraph.start(opts)
    call_graph_dump_path = Path.join(build_dir, Reflection.call_graph_dump_file_name())
    CallGraph.maybe_load(call_graph, call_graph_dump_path)

    {call_graph, call_graph_dump_path}
  end

  @doc """
  Loads IR PLT from a dump file if the file exists or creates an empty PLT.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/maybe_load_ir_plt_1/README.md
  """
  @spec maybe_load_ir_plt(T.file_path()) :: {PLT.t(), String.t()}
  def maybe_load_ir_plt(build_dir) do
    ir_plt = PLT.start()
    ir_plt_dump_path = Path.join(build_dir, Reflection.ir_plt_dump_file_name())
    PLT.maybe_load(ir_plt, ir_plt_dump_path)

    {ir_plt, ir_plt_dump_path}
  end

  @doc """
  Loads module digest PLT from a dump file if the file exists or creates an empty PLT.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/maybe_load_module_digest_plt_1/README.md
  """
  @spec maybe_load_module_digest_plt(T.file_path(), T.opts()) :: {PLT.t(), String.t()}
  def maybe_load_module_digest_plt(build_dir, opts \\ []) do
    module_digest_plt = PLT.start(opts)

    module_digest_plt_dump_path =
      Path.join(build_dir, Reflection.module_digest_plt_dump_file_name())

    PLT.maybe_load(module_digest_plt, module_digest_plt_dump_path)

    {module_digest_plt, module_digest_plt_dump_path}
  end

  @doc """
  Returns what the client's data layer is compiled with, derived from the queries the given
  pages reach.

  `:entity_types` are the types a client can ever hold - every window's own type and everything
  it includes. Nothing else can reach a client's database, so nothing else is worth telling it
  about.

  `:ordered_string_pairs` are the {entity type, attribute name} pairs those queries order by on
  :string attributes - the pairs whose sort-key companions the client computes at ingest,
  derived from the same registered queries the server derives its companion columns from.
  """
  @spec build_sync_constants(list(module), CallGraph.t()) :: %{
          entity_types: MapSet.t(module),
          ordered_string_pairs: MapSet.t({module, atom})
        }
  def build_sync_constants(page_modules, call_graph) do
    graph = CallGraph.get_graph(call_graph)
    templatables = page_modules ++ Reflection.list_components()
    analysis = CallGraph.server_callback_analysis_by_templatable(graph, templatables)

    terms = Enum.flat_map(page_modules, &page_query_terms(&1, call_graph, analysis))

    entity_types =
      Enum.reduce(terms, MapSet.new(), fn term, types ->
        MapSet.union(types, Registry.entity_types(term))
      end)

    %{entity_types: entity_types, ordered_string_pairs: Registry.ordered_string_pairs(terms)}
  end

  @doc """
  Given a module digests diff, updates the IR persistent lookup table (PLT)
  by deleting entries for modules that have been removed,
  rebuilding the IR of modules that have been edited,
  and adding the IR of new modules.
  """
  @spec patch_ir_plt!(PLT.t(), map) :: PLT.t()
  def patch_ir_plt!(ir_plt, module_digests_diff) do
    # TODO: Remove this flag and the argument it feeds to rebuild_ir_plt_entry!/3
    # when resolve_beam_source/2 goes (see the removal note there).
    umbrella? = Reflection.umbrella?()

    delete_tasks =
      TaskUtils.async_many(module_digests_diff.removed_modules, &PLT.delete(ir_plt, &1))

    rebuild_tasks =
      TaskUtils.async_many(
        module_digests_diff.edited_modules ++ module_digests_diff.added_modules,
        &rebuild_ir_plt_entry!(ir_plt, &1, umbrella?)
      )

    Task.await_many(delete_tasks, :infinity)
    Task.await_many(rebuild_tasks, :infinity)

    ir_plt
  end

  @doc """
  Keeps only those IR expressions that are function definitions of the given reachable MFAs.
  For protocol modules, additionally drops the consolidated impl_for/1 and struct_impl_for/1
  clauses that return implementations not included in the given reachable MFAs.
  """
  @spec prune_module_def(IR.ModuleDefinition.t(), list(mfa)) :: IR.ModuleDefinition.t()
  def prune_module_def(module_def_ir, reachable_mfas) do
    module = module_def_ir.module.value

    module_reachable_mfas =
      reachable_mfas
      |> Enum.filter(fn {reachable_module, _function, _arity} -> reachable_module == module end)
      |> MapSet.new()

    function_defs =
      module_def_ir.body.expressions
      |> Enum.filter(fn
        %IR.FunctionDefinition{name: function, arity: arity} ->
          MapSet.member?(module_reachable_mfas, {module, function, arity})

        _fallback ->
          false
      end)
      |> maybe_prune_protocol_dispatcher_function_defs(module, reachable_mfas)

    %IR.ModuleDefinition{
      module: module_def_ir.module,
      body: %IR.Block{expressions: function_defs}
    }
  end

  @doc """
  Raises a compilation error if any page module lacks a specified route or layout.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/validate_page_modules_1/README.md
  """
  @spec validate_page_modules(list(module)) :: :ok
  def validate_page_modules(page_modules) do
    Enum.each(page_modules, fn page_module ->
      if !Reflection.has_function?(page_module, :__route__, 0) do
        module_name = Reflection.module_name(page_module)

        raise Hologram.CompileError,
          message:
            "page '#{module_name}' doesn't have a route specified (use the route/1 macro to fix it)"
      end

      if !Reflection.has_function?(page_module, :__layout_module__, 0) do
        module_name = Reflection.module_name(page_module)

        raise Hologram.CompileError,
          message:
            "page '#{module_name}' doesn't have a layout module specified (use the layout/1 macro to fix it)"
      end
    end)
  end

  @doc """
  Validates the from_query slot bindings of every component reachable from the given
  page modules - a parameterized builder's argument names must bind like-named
  declared slots (today, declared props) on the consuming component.

  Raises Hologram.CompileError when a capture argument names no declared slot, or
  when an argument position is named by no clause of the capture's target.
  """
  @spec validate_slot_bindings!(list(module), CallGraph.t()) :: :ok
  def validate_slot_bindings!(page_modules, call_graph) do
    graph = CallGraph.get_graph(call_graph)
    templatables = page_modules ++ Reflection.list_components()
    analysis = CallGraph.server_callback_analysis_by_templatable(graph, templatables)

    page_modules
    |> Enum.flat_map(&page_component_modules(&1, call_graph, analysis))
    |> Enum.uniq()
    |> Enum.each(&QueryExtractor.validate_slot_bindings!/1)
  end

  defp create_entry_file(js, entry_name, tmp_dir) do
    entry_file_path = Path.join(tmp_dir, "#{entry_name}.entry.js")
    File.write!(entry_file_path, js)

    entry_file_path
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

  defp filter_elixir_mfas(mfas) do
    Enum.filter(mfas, fn {module, _function, _arity} -> Reflection.elixir_module?(module) end)
  end

  defp filter_erlang_mfas(mfas) do
    Enum.filter(mfas, fn {module, _function, _arity} -> Reflection.erlang_module?(module) end)
  end

  defp get_package_json_digest(assets_dir) do
    assets_dir
    |> Path.join("package.json")
    |> File.read!()
    |> CryptographicUtils.digest(:sha256, :binary)
  end

  defp included_protocol_implementations(reachable_mfas, protocol) do
    reachable_mfas
    |> Enum.map(fn {module, _function, _arity} -> module end)
    |> Enum.uniq()
    |> Enum.filter(&(Reflection.protocol_implementation(&1) == protocol))
    |> MapSet.new()
  end

  defp keep_protocol_dispatcher_function_def?(
         %IR.FunctionDefinition{name: function, arity: 1, clause: clause},
         protocol,
         included_impls
       )
       when function in [:impl_for, :struct_impl_for] do
    case clause do
      %IR.FunctionClause{body: %IR.Block{expressions: [%IR.AtomType{value: value}]}} ->
        Reflection.protocol_implementation(value) != protocol or
          MapSet.member?(included_impls, value)

      _clause ->
        true
    end
  end

  defp keep_protocol_dispatcher_function_def?(_function_def, _protocol, _included_impls), do: true

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
  defp maybe_prune_protocol_dispatcher_function_defs(function_defs, module, reachable_mfas) do
    if Reflection.protocol?(module) do
      included_impls = included_protocol_implementations(reachable_mfas, module)

      Enum.filter(
        function_defs,
        &keep_protocol_dispatcher_function_def?(&1, module, included_impls)
      )
    else
      function_defs
    end
  end

  defp page_component_modules(page_module, call_graph, analysis) do
    call_graph
    |> CallGraph.list_page_mfas(page_module, analysis)
    |> Enum.map(fn {module, _function, _arity} -> module end)
    |> Enum.uniq()
    |> Enum.filter(&Reflection.component?/1)
  end

  defp page_query_terms(page_module, call_graph, analysis) do
    page_module
    |> page_component_modules(call_graph, analysis)
    |> Enum.flat_map(&QueryExtractor.extract_module_queries/1)
  end

  # TODO: Drop the umbrella? param and resolve the beam path with :code.which/1
  # when resolve_beam_source/2 goes (see the removal note there).
  defp page_window_ids(page_module, call_graph, analysis) do
    page_module
    |> page_query_terms(call_graph, analysis)
    |> Enum.map(&window_id/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp rebuild_ir_plt_entry!(ir_plt, module, umbrella?) do
    # A nil beam source must not reach IR.for_module/2 - it resolves a nil one
    # with :code.which/1, which is exactly the stale path that yielded nil here.
    if beam_source = resolve_beam_source(module, umbrella?) do
      PLT.put(ir_plt, module, IR.for_module(module, beam_source))
    end
  end

  # TODO: Drop the umbrella? param and resolve the beam path with :code.which/1
  # when resolve_beam_source/2 goes (see the removal note there).
  defp rebuild_module_digest_plt_entry!(module, module_digest_plt, umbrella?) do
    beam_source = resolve_beam_source(module, umbrella?)

    if beam_source do
      digest =
        beam_source
        |> Reflection.beam_defs()
        # Fast and deterministic for change detection
        |> :erlang.phash2()

      PLT.put(module_digest_plt, module, digest)
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

  defp render_client_config do
    ~s/{errorOverlay: #{Hologram.client_error_overlay?()}, stacktraces: #{Hologram.client_stacktraces?()}}/
  end

  # What a client needs to read its own rows: a value's type is not recoverable from the value
  # itself - a date, an enum and a uuid all arrive as strings - so reading one back means knowing
  # the attribute it belongs to, which is what this says.
  #
  # It rides with the bundle rather than with the entity modules, for two reasons. A module says
  # this through functions nothing calls statically, so nothing keeps them: the caller names them
  # on a module it is handed, an edge no call graph can see. And a module travels in its PAGE's
  # bundle, while the database holds every type the app syncs - a row of a type the current page
  # never mentions still has to be read.
  #
  # Server-only attributes are named here, values and all: what the client holds of one is the
  # knowledge that it exists and is not for it, which is what lets a read of that field say so
  # rather than answer nil.
  defp render_entity_model(entity_types) do
    entity_types
    |> Enum.map(&{Codec.encode_enum_value(&1), render_entity_model_entry(&1)})
    |> render_json_object()
  end

  defp render_entity_model_entry(entity_type) do
    attributes =
      entity_type.__attributes__()
      |> Enum.concat(entity_type.__system_attributes__())
      |> Enum.map(fn {name, type, _opts} -> {Atom.to_string(name), Jason.encode!(type)} end)
      |> render_json_object()

    server_only =
      entity_type
      |> Entity.server_only_attribute_names()
      |> Enum.sort()
      |> Jason.encode!()

    render_json_object([
      {"attributes", attributes},
      {"relationships", render_relationships(entity_type)},
      {"serverOnly", server_only}
    ])
  end

  # Keys are written in sorted order rather than the order a map hands them over in - that one
  # follows the atom table, which follows what the build happened to load first, and the bundle
  # this text ends up in is addressed by its content.
  defp render_json_object(members) do
    members
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join(",", fn {key, value} -> ~s/#{Jason.encode!(key)}:#{value}/ end)
    |> then(&"{#{&1}}")
  end

  # A to-many is spelled apart from a to-one because they are read apart: a to-many is assembled
  # from the relationship facts, a to-one is followed through the reference field the row carries.
  defp render_relationships(entity_type) do
    entity_type.__relationships__()
    |> Enum.map(fn {name, target, _opts} ->
      {Atom.to_string(name), render_relationship(target)}
    end)
    |> render_json_object()
  end

  defp render_relationship(target) when is_list(target) do
    render_relationship_entry(hd(target), true)
  end

  defp render_relationship(target), do: render_relationship_entry(target, false)

  defp render_relationship_entry(target, to_many?) do
    type =
      target
      |> Codec.encode_enum_value()
      |> Jason.encode!()

    render_json_object([{"toMany", Jason.encode!(to_many?)}, {"type", type}])
  end

  defp render_ordered_string_pairs(ordered_string_pairs) do
    ordered_string_pairs
    |> Enum.map(fn {entity_type, attribute} ->
      [Codec.encode_enum_value(entity_type), Atom.to_string(attribute)]
    end)
    |> Enum.sort()
    |> Jason.encode!()
  end

  # What the bundle was built against, said by the bundle itself. It has to be baked in rather
  # than handed over at page render: the check these answer is whether a client's JAVASCRIPT is
  # stale, and a value the current server puts in the page would always agree with the current
  # server.
  #
  # A build declaring no entity types says NULL, explicitly: it has no database - the application
  # tree gates the whole data layer on exactly that - so a client reads one unambiguous value
  # instead of probing for a missing global. An empty OBJECT would be worse than nothing at all:
  # `{}` is truthy, so every "does this bundle sync?" check would pass on a bundle that does not.
  defp render_sync_constants(sync_constants) do
    if Reflection.list_entities() == [] do
      ~s/globalThis.Hologram.sync = null;/
    else
      model = render_entity_model(sync_constants.entity_types)
      pairs = render_ordered_string_pairs(sync_constants.ordered_string_pairs)

      ~s/globalThis.Hologram.sync = {model: #{model}, modelHash: "#{Model.hash()}", orderedStringPairs: #{pairs}, protocolVersion: #{Frame.protocol_version()}};/
    end
  end

  defp render_elixir_function_defs(mfas, ir_plt, async_mfas) do
    mfas
    |> filter_elixir_mfas()
    |> group_mfas_by_module()
    |> Enum.sort()
    |> TaskUtils.async_many(fn {module, _module_mfas} ->
      ir_plt
      |> PLT.get!(module)
      |> prune_module_def(mfas)
      |> Encoder.encode_ir(%Context{module: module, async_mfas: async_mfas})
    end)
    |> Task.await_many(:infinity)
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
            %Context{module: module}
          )
        end)

      :error ->
        []
    end
  end

  defp render_module_metadata_registration(mfas) do
    mfas
    |> filter_elixir_mfas()
    |> Enum.map(fn {module, _function, _arity} -> module end)
    |> Enum.uniq()
    |> Encoder.encode_module_metadata_registration()
  end

  defp render_erlang_function_defs(mfas, erlang_js_dir) do
    mfas
    |> filter_erlang_mfas()
    |> TaskUtils.async_many(fn {module, function, arity} ->
      Encoder.encode_erlang_function(module, function, arity, erlang_js_dir)
    end)
    |> Task.await_many(:infinity)
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
  # build_ir_plt/1, build_module_digest_plt!/1, patch_ir_plt!/2,
  # rebuild_ir_plt_entry!/3 and rebuild_module_digest_plt_entry!/3 - their
  # bodies go back to resolving the beam path with :code.which/1 directly.
  defp resolve_beam_source(module, true), do: Reflection.beam_source(module)

  defp resolve_beam_source(module, false) do
    beam_path = :code.which(module)

    if beam_path != :non_existing do
      beam_path
    end
  end

  defp window_id(term) do
    term
    |> Window.derive()
    |> Registry.id()
  end
end
