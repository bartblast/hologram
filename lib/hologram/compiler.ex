defmodule Hologram.Compiler do
  @moduledoc false

  alias Hologram.Commons.CryptographicUtils
  alias Hologram.Commons.PLT
  alias Hologram.Commons.TaskUtils
  alias Hologram.Commons.Types, as: T
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR
  alias Hologram.Reflection

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

    call_graph
  end

  @doc """
  Builds IR persistent lookup table (PLT) of all modules in the project.
  """
  @spec build_ir_plt :: PLT.t()
  def build_ir_plt do
    build_ir_plt(build_module_beam_path_plt())
  end

  @doc """
  Builds IR persistent lookup table (PLT) of all modules in the project using the given module BEAM path PLT.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/build_ir_plt_1/README.md
  """
  @spec build_ir_plt(PLT.t()) :: PLT.t()
  def build_ir_plt(module_beam_path_plt) do
    ir_plt = PLT.start()

    Reflection.list_elixir_modules()
    |> TaskUtils.async_many(fn module ->
      beam_path = get_module_beam_path(module_beam_path_plt, module)

      if beam_path != :non_existing do
        ir = IR.for_module(module, beam_path)
        PLT.put(ir_plt, module, ir)
      end
    end)
    |> Task.await_many(:infinity)

    ir_plt
  end

  @doc """
  Builds module BEAM path persistent lookup table (PLT) of all modules in the project.
  """
  @spec build_module_beam_path_plt :: PLT.t()
  def build_module_beam_path_plt do
    module_beam_path_plt = PLT.start()

    Reflection.list_elixir_modules()
    |> TaskUtils.async_many(fn module ->
      beam_path = :code.which(module)
      PLT.put(module_beam_path_plt, module, beam_path)
    end)
    |> Task.await_many(:infinity)

    module_beam_path_plt
  end

  @doc """
  Builds a persistent lookup table (PLT) containing the BEAM defs digests for all the modules in the project.
  Mutates module BEAM path PLT.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/build_module_digest_plt!_1/README.md
  """
  @spec build_module_digest_plt!(PLT.t()) :: PLT.t()
  def build_module_digest_plt!(module_beam_path_plt) do
    module_digest_plt = PLT.start()

    Reflection.list_elixir_modules()
    |> TaskUtils.async_many(
      &rebuild_module_digest_plt_entry!(&1, module_digest_plt, module_beam_path_plt)
    )
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

    page_digest_plt = PLT.start(items: page_digest_plt_items)

    page_digest_plt_dump_path =
      Path.join([opts[:build_dir], Reflection.page_digest_plt_dump_file_name()])

    {page_digest_plt, page_digest_plt_dump_path}
  end

  @doc """
  Builds JavaScript code for the given Hologram page.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/build_page_js_4/README.md
  """
  @spec build_page_js(module, CallGraph.t(), PLT.t(), T.file_path()) :: String.t()
  def build_page_js(page_module, call_graph, ir_plt, js_dir) do
    mfas = CallGraph.list_page_mfas(call_graph, page_module)
    erlang_js_dir = Path.join(js_dir, "erlang")

    erlang_function_defs =
      mfas
      |> render_erlang_function_defs(erlang_js_dir)
      |> render_block()

    elixir_function_defs =
      mfas
      |> render_elixir_function_defs(ir_plt)
      |> render_block()

    """
    "use strict";

    import PerformanceTimer from "#{js_dir}/performance_timer.mjs";    

    const startTime = performance.now();

    globalThis.hologram.pageReachableFunctionDefs = (deps) => {
      const {
        Bitstring,
        HologramBoxedError,
        HologramInterpreterError,
        Interpreter,
        MemoryStorage,
        Type,
        Utils,
      } = deps;#{erlang_function_defs}#{elixir_function_defs}
    }

    globalThis.hologram.pageScriptLoaded = true;
    document.dispatchEvent(new CustomEvent("hologram:pageScriptLoaded"));

    console.debug("Hologram: page script executed in", PerformanceTimer.diff(startTime));\
    """
  end

  @doc """
  Builds Hologram runtime JavaScript source code.
  """
  @spec build_runtime_js(list(mfa), PLT.t(), T.file_path()) :: String.t()
  def build_runtime_js(runtime_mfas, ir_plt, js_dir) do
    erlang_function_defs =
      runtime_mfas
      |> render_erlang_function_defs("#{js_dir}/erlang")
      |> render_block()

    elixir_function_defs =
      runtime_mfas
      |> render_elixir_function_defs(ir_plt)
      |> render_block()

    """
    "use strict";

    import Bitstring from "#{js_dir}/bitstring.mjs";
    import Hologram from "#{js_dir}/hologram.mjs";
    import HologramBoxedError from "#{js_dir}/errors/boxed_error.mjs";
    import HologramInterpreterError from "#{js_dir}/errors/interpreter_error.mjs";
    import Interpreter from "#{js_dir}/interpreter.mjs";
    import MemoryStorage from "#{js_dir}/memory_storage.mjs";
    import PerformanceTimer from "#{js_dir}/performance_timer.mjs";
    import Type from "#{js_dir}/type.mjs";
    import Utils from "#{js_dir}/utils.mjs";

    const startTime = PerformanceTimer.start();#{erlang_function_defs}#{elixir_function_defs}

    document.addEventListener("hologram:pageScriptLoaded", () => Hologram.run());

    if (globalThis.hologram.pageScriptLoaded) {
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
      "--target=es2020"
    ]

    {_exit_msg, exit_status} = System.cmd(opts[:esbuild_bin_path], esbuild_cmd, parallelism: true)

    if exit_status != 0 do
      raise RuntimeError,
        message:
          "esbuild bundler failed for entry file: #{entry_file_path} (probably there were JavaScript syntax errors)"
    end

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

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/create_page_entry_files_4/README.md
  """
  @spec create_page_entry_files(list(module), CallGraph.t(), PLT.t(), T.opts()) ::
          list({module, T.file_path()})
  def create_page_entry_files(page_modules, call_graph, ir_plt, opts) do
    page_modules
    |> TaskUtils.async_many(fn page_module ->
      entry_name = Reflection.module_name(page_module)

      entry_file_path =
        page_module
        |> build_page_js(call_graph, ir_plt, opts[:js_dir])
        |> create_entry_file(entry_name, opts[:tmp_dir])

      {page_module, entry_file_path}
    end)
    |> Task.await_many(:infinity)
  end

  @doc """
  Creates runtime bundle entry file.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/create_runtime_entry_file_3/README.md
  """
  @spec create_runtime_entry_file(list(mfa), PLT.t(), T.opts()) :: T.file_path()
  def create_runtime_entry_file(runtime_mfas, ir_plt, opts) do
    runtime_mfas
    |> build_runtime_js(ir_plt, opts[:js_dir])
    |> create_entry_file("runtime", opts[:tmp_dir])
  end

  @doc """
  Compares two module digest PLTs and returns the added, removed, and updated modules lists.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/diff_module_digest_plts_2/README.md
  """
  @spec diff_module_digest_plts(PLT.t(), PLT.t()) :: %{
          added_modules: list(module),
          removed_modules: list(module),
          updated_modules: list(module)
        }
  def diff_module_digest_plts(old_plt, new_plt) do
    old_modules = mapset_from_plt_keys(old_plt)
    new_modules = mapset_from_plt_keys(new_plt)

    removed_modules =
      old_modules
      |> MapSet.difference(new_modules)
      |> MapSet.to_list()

    added_modules =
      new_modules
      |> MapSet.difference(old_modules)
      |> MapSet.to_list()

    updated_modules =
      old_modules
      |> MapSet.intersection(new_modules)
      |> MapSet.to_list()
      |> Enum.filter(&(PLT.get!(old_plt, &1) != PLT.get!(new_plt, &1)))

    %{
      added_modules: added_modules,
      removed_modules: removed_modules,
      updated_modules: updated_modules
    }
  end

  @doc """
  Formats the given JavaScript files with Biome.

  Benchmark: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/format_files_2/README.md
  """
  @spec format_files(list(T.file_path()), T.opts()) ::
          {Collectable.t(), exit_status :: non_neg_integer()}
  # sobelow_skip ["CI.System"]
  def format_files(file_paths, opts) do
    cmd = ["format", "--write" | file_paths]
    {exit_msg, exit_status} = System.cmd(opts[:formatter_bin_path], cmd, parallelism: true)

    if exit_status != 0 do
      raise RuntimeError,
        message: "Biome formatter failed (probably there were JavaScript syntax errors)"
    end

    exit_msg
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
  def install_js_deps(assets_dir, build_dir) do
    opts = [cd: assets_dir, into: IO.stream(:stdio, :line)]
    {_result, exit_status} = System.cmd("npm", ["install"], opts)

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
  @spec maybe_load_call_graph(T.file_path()) :: {CallGraph.t(), String.t()}
  def maybe_load_call_graph(build_dir) do
    call_graph = CallGraph.start()
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
  Loads module BEAM path PLT from a dump file if the file exists or creates an empty PLT.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/maybe_load_module_beam_path_plt_1/README.md
  """
  @spec maybe_load_module_beam_path_plt(T.file_path()) :: {PLT.t(), String.t()}
  def maybe_load_module_beam_path_plt(build_dir) do
    module_beam_path_plt = PLT.start()

    module_beam_path_plt_dump_path =
      Path.join(build_dir, Reflection.module_beam_path_plt_dump_file_name())

    PLT.maybe_load(module_beam_path_plt, module_beam_path_plt_dump_path)

    {module_beam_path_plt, module_beam_path_plt_dump_path}
  end

  @doc """
  Loads module digest PLT from a dump file if the file exists or creates an empty PLT.

  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/compiler/maybe_load_module_digest_plt_1/README.md
  """
  @spec maybe_load_module_digest_plt(T.file_path()) :: {PLT.t(), String.t()}
  def maybe_load_module_digest_plt(build_dir) do
    module_digest_plt = PLT.start()

    module_digest_plt_dump_path =
      Path.join(build_dir, Reflection.module_digest_plt_dump_file_name())

    PLT.maybe_load(module_digest_plt, module_digest_plt_dump_path)

    {module_digest_plt, module_digest_plt_dump_path}
  end

  @doc """
  Given a module digests diff, updates the IR persistent lookup table (PLT)
  by deleting entries for modules that have been removed,
  rebuilding the IR of modules that have been updated,
  and adding the IR of new modules.
  """
  @spec patch_ir_plt!(PLT.t(), map, PLT.t()) :: PLT.t()
  def patch_ir_plt!(ir_plt, module_digests_diff, module_beam_path_plt) do
    delete_tasks =
      TaskUtils.async_many(module_digests_diff.removed_modules, &PLT.delete(ir_plt, &1))

    rebuild_tasks =
      TaskUtils.async_many(
        module_digests_diff.updated_modules ++ module_digests_diff.added_modules,
        &rebuild_ir_plt_entry!(ir_plt, &1, module_beam_path_plt)
      )

    Task.await_many(delete_tasks, :infinity)
    Task.await_many(rebuild_tasks, :infinity)

    ir_plt
  end

  @doc """
  Keeps only those IR expressions that are function definitions of the given reachable MFAs.
  """
  @spec prune_module_def(IR.ModuleDefinition.t(), list(mfa)) :: IR.ModuleDefinition.t()
  def prune_module_def(module_def_ir, reachable_mfas) do
    module = module_def_ir.module.value

    module_reachable_mfas =
      reachable_mfas
      |> Enum.filter(fn {reachable_module, _function, _arity} -> reachable_module == module end)
      |> MapSet.new()

    function_defs =
      Enum.filter(module_def_ir.body.expressions, fn
        %IR.FunctionDefinition{name: function, arity: arity} ->
          MapSet.member?(module_reachable_mfas, {module, function, arity})

        _fallback ->
          false
      end)

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

  defp create_entry_file(js, entry_name, tmp_dir) do
    entry_file_path = Path.join(tmp_dir, "#{entry_name}.entry.js")
    File.write!(entry_file_path, js)

    entry_file_path
  end

  defp filter_elixir_mfas(mfas) do
    Enum.filter(mfas, fn {module, _function, _arity} -> Reflection.elixir_module?(module) end)
  end

  defp filter_erlang_mfas(mfas) do
    Enum.filter(mfas, fn {module, _function, _arity} -> Reflection.erlang_module?(module) end)
  end

  defp get_module_beam_path(module_beam_path_plt, module) do
    case PLT.get(module_beam_path_plt, module) do
      {:ok, path} ->
        path

      :error ->
        path = :code.which(module)
        PLT.put(module_beam_path_plt, module, path)
        path
    end
  end

  defp get_package_json_digest(assets_dir) do
    assets_dir
    |> Path.join("package.json")
    |> File.read!()
    |> CryptographicUtils.digest(:sha256, :binary)
  end

  defp mapset_from_plt_keys(plt) do
    plt
    |> PLT.get_all()
    |> Map.keys()
    |> MapSet.new()
  end

  defp rebuild_ir_plt_entry!(ir_plt, module, module_beam_path_plt) do
    beam_path = PLT.get!(module_beam_path_plt, module)
    PLT.put(ir_plt, module, IR.for_module(module, beam_path))
  end

  defp rebuild_module_digest_plt_entry!(module, module_digest_plt, module_beam_path_plt) do
    beam_path = get_module_beam_path(module_beam_path_plt, module)

    if beam_path != :non_existing do
      data =
        beam_path
        |> Reflection.beam_defs()
        |> :erlang.term_to_binary(compressed: 0)

      digest = CryptographicUtils.digest(data, :sha256, :binary)
      PLT.put(module_digest_plt, module, digest)
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

  defp render_elixir_function_defs(mfas, ir_plt) do
    mfas
    |> filter_elixir_mfas()
    |> group_mfas_by_module()
    |> Enum.sort()
    |> TaskUtils.async_many(fn {module, module_mfas} ->
      ir_plt
      |> PLT.get!(module)
      |> prune_module_def(module_mfas)
      |> Encoder.encode_ir(%Context{module: module})
    end)
    |> Task.await_many(:infinity)
    |> Enum.join("\n\n")
  end

  defp render_erlang_function_defs(mfas, erlang_source_dir) do
    mfas
    |> filter_erlang_mfas()
    |> TaskUtils.async_many(fn {module, function, arity} ->
      Encoder.encode_erlang_function(module, function, arity, erlang_source_dir)
    end)
    |> Task.await_many(:infinity)
    |> Enum.join("\n\n")
  end
end
