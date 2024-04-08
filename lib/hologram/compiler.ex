defmodule Hologram.Compiler do
  alias Hologram.Commons.CryptographicUtils
  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR

  @doc """
  Builds a persistent lookup table (PLT) containing the BEAM defs digests for all the modules in the project.
  """
  @spec build_module_digest_plt() :: PLT.t()
  def build_module_digest_plt do
    plt = PLT.start()

    Reflection.list_elixir_modules()
    |> Task.async_stream(&rebuild_module_digest_plt_entry(plt, &1))
    |> Stream.run()

    plt
  end

  @doc """
  Builds JavaScript code for the given Hologram page.
  """
  @spec build_page_js(module, CallGraph.t(), PLT.t(), String.t()) :: String.t()
  def build_page_js(page_module, call_graph, ir_plt, source_dir) do
    mfas = list_page_mfas(call_graph, page_module)
    erlang_source_dir = source_dir <> "/erlang"

    erlang_function_defs =
      mfas
      |> render_erlang_function_defs(erlang_source_dir)
      |> render_block()

    elixir_function_defs =
      mfas
      |> render_elixir_function_defs(ir_plt)
      |> render_block()

    """
    "use strict";

    window.__hologramPageReachableFunctionDefs__ = (deps) => {
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

    window.__hologramPageScriptLoaded__ = true;
    document.dispatchEvent(new CustomEvent("hologram:pageScriptLoaded"));\
    """
  end

  @doc """
  Builds Hologram runtime JavaScript source code.
  """
  @spec build_runtime_js(String.t(), CallGraph.t(), PLT.t()) :: String.t()
  def build_runtime_js(source_dir, call_graph, ir_plt) do
    mfas = list_runtime_mfas(call_graph)

    erlang_function_defs =
      mfas
      |> render_erlang_function_defs("#{source_dir}/erlang")
      |> render_block()

    elixir_function_defs =
      mfas
      |> render_elixir_function_defs(ir_plt)
      |> render_block()

    """
    "use strict";

    import Bitstring from "#{source_dir}/bitstring.mjs";
    import Hologram from "#{source_dir}/hologram.mjs";
    import HologramBoxedError from "#{source_dir}/errors/boxed_error.mjs";
    import HologramInterpreterError from "#{source_dir}/errors/interpreter_error.mjs";
    import Interpreter from "#{source_dir}/interpreter.mjs";
    import MemoryStorage from "#{source_dir}/memory_storage.mjs";
    import Type from "#{source_dir}/type.mjs";
    import Utils from "#{source_dir}/utils.mjs";#{erlang_function_defs}#{elixir_function_defs}

    document.addEventListener("hologram:pageScriptLoaded", () => Hologram.run());

    if (window.__hologramPageScriptLoaded__) {
      document.dispatchEvent(new CustomEvent("hologram:pageScriptLoaded"));
    }\
    """
  end

  @doc """
  Bundles the given JavaScript code into a JavaScript file and its source map.
  The generated file names contain the hex digest of the bundled JavaScript file content.

  ## Examples

      iex> bundle(js, opts)
      {"caf8f4e27584852044eb27a37c5eddfd",
       "priv/static/my_script-caf8f4e27584852044eb27a37c5eddfd.js",
       "priv/static/my_script-caf8f4e27584852044eb27a37c5eddfd.js.map"}
  """
  @spec bundle(String.t(), keyword) :: {String.t(), String.t(), String.t()}
  # sobelow_skip ["CI.System"]
  def bundle(js, opts) do
    entry_name = opts[:entry_name]
    esbuild_path = opts[:esbuild_path]
    tmp_dir = opts[:tmp_dir]
    bundle_dir = opts[:bundle_dir]
    bundle_name = opts[:bundle_name]

    File.mkdir_p!(tmp_dir)
    File.mkdir_p!(bundle_dir)

    entry_file_path = tmp_dir <> "/#{entry_name}.entry.js"
    File.write!(entry_file_path, js)

    format_entry_file(entry_file_path, opts)

    bundle_path = "#{bundle_dir}/#{bundle_name}.js"

    esbuild_cmd = [
      entry_file_path,
      "--bundle",
      "--log-level=warning",
      "--minify",
      "--outfile=#{bundle_path}",
      "--sourcemap",
      "--target=es2020"
    ]

    System.cmd(esbuild_path, esbuild_cmd, env: [], parallelism: true)

    digest =
      bundle_path
      |> File.read!()
      |> CryptographicUtils.digest(:md5, :hex)

    bundle_path_with_digest = "#{bundle_dir}/#{bundle_name}-#{digest}.js"

    source_map_path = bundle_path <> ".map"
    source_map_path_with_digest = bundle_path_with_digest <> ".map"

    File.rename!(bundle_path, bundle_path_with_digest)
    File.rename!(source_map_path, source_map_path_with_digest)

    js_with_replaced_source_map_url =
      bundle_path_with_digest
      |> File.read!()
      |> String.replace(
        "//# sourceMappingURL=#{bundle_name}.js.map",
        "//# sourceMappingURL=#{bundle_name}-#{digest}.js.map"
      )

    File.write!(bundle_path_with_digest, js_with_replaced_source_map_url)

    {digest, bundle_path_with_digest, source_map_path_with_digest}
  end

  @doc """
  Compares two module digest PLTs and returns the added, removed, and updated modules lists.
  """
  @spec diff_module_digest_plts(PLT.t(), PLT.t()) :: %{
          added_modules: list,
          removed_modules: list,
          updated_modules: list
        }
  def diff_module_digest_plts(old_plt, new_plt) do
    old_mapset = mapset_from_plt(old_plt)
    new_mapset = mapset_from_plt(new_plt)

    removed_modules =
      old_mapset
      |> MapSet.difference(new_mapset)
      |> MapSet.to_list()

    added_modules =
      new_mapset
      |> MapSet.difference(old_mapset)
      |> MapSet.to_list()

    updated_modules =
      old_mapset
      |> MapSet.intersection(new_mapset)
      |> MapSet.to_list()
      |> Enum.filter(&(PLT.get(old_plt, &1) != PLT.get(new_plt, &1)))

    %{
      added_modules: added_modules,
      removed_modules: removed_modules,
      updated_modules: updated_modules
    }
  end

  @doc """
  Groups the given MFAs by module.
  """
  @spec group_mfas_by_module(list(mfa)) :: %{module => mfa}
  def group_mfas_by_module(mfas) do
    Enum.group_by(mfas, fn {module, _function, _arity} -> module end)
  end

  @doc """
  Installs JavaScript deps specified in package.json located in the given dir.
  """
  @spec install_js_deps(String.t()) :: :ok
  def install_js_deps(dir) do
    opts = [cd: dir, into: IO.stream(:stdio, :line)]
    System.cmd("npm", ["install"], opts)
    :ok
  end

  @doc """
  Returns the list of MFAs that are reachable by the given page.
  Functions required by the runtime as well as manually ported Elixir functions are excluded.
  """
  @spec list_page_mfas(CallGraph.t(), module) :: list(mfa)
  def list_page_mfas(call_graph, page_module) do
    call_graph_clone = CallGraph.clone(call_graph)
    layout_module = page_module.__layout_module__()
    runtime_mfas = list_runtime_mfas(call_graph)

    call_graph_clone
    |> CallGraph.add_edge(page_module, {page_module, :__layout_module__, 0})
    |> CallGraph.add_edge(page_module, {page_module, :__layout_props__, 0})
    |> CallGraph.add_edge(page_module, {page_module, :__props__, 0})
    |> CallGraph.add_edge(page_module, {page_module, :action, 3})
    |> CallGraph.add_edge(page_module, {page_module, :template, 0})
    |> CallGraph.add_edge(page_module, {layout_module, :__props__, 0})
    |> CallGraph.add_edge(page_module, {layout_module, :action, 3})
    |> CallGraph.add_edge(page_module, {layout_module, :template, 0})
    |> remove_call_graph_vertices_of_manually_ported_elixir_functions()
    |> CallGraph.reachable(page_module)
    |> Enum.filter(&is_tuple/1)
    |> Kernel.--(runtime_mfas)
  end

  @doc """
  Lists MFAs required by the runtime JS script.
  Manually ported Elixir functions are excluded.
  """
  @spec list_runtime_mfas(CallGraph.t()) :: list(mfa)
  def list_runtime_mfas(call_graph) do
    call_graph_clone = CallGraph.clone(call_graph)

    entry_mfas =
      []
      |> include_mfas_used_by_asset_path_registry_class()
      |> include_mfas_used_by_component_registry_class()
      |> include_mfas_used_frequently_on_the_client()
      |> include_mfas_used_by_interpreter_class()
      |> include_mfas_used_by_manually_ported_code_module()
      |> include_mfas_used_by_operation_class()
      |> include_mfas_used_by_renderer_class()
      |> include_mfas_used_by_type_class()
      |> Enum.uniq()

    call_graph_clone
    |> add_call_graph_edges_for_erlang_functions()
    |> remove_call_graph_vertices_of_manually_ported_elixir_functions()
    |> CallGraph.reachable_mfas(entry_mfas)
    # Some protocol implementations are referenced but not actually implemented, e.g. Collectable.Atom
    |> Enum.reject(fn {module, _function, _arity} -> !Reflection.module?(module) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Given a diff of changes, updates the IR persistent lookup table (PLT)
  by deleting entries for modules that have been removed,
  rebuilding the IR of modules that have been updated,
  and adding the IR of new modules.
  """
  @spec patch_ir_plt(PLT.t(), map) :: PLT.t()
  def patch_ir_plt(ir_plt, diff) do
    diff.removed_modules
    |> Task.async_stream(&PLT.delete(ir_plt, &1))
    |> Stream.run()

    (diff.updated_modules ++ diff.added_modules)
    |> Task.async_stream(&rebuild_ir_plt_entry(ir_plt, &1))
    |> Stream.run()

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

  # Add call graph edges for Erlang functions depending on other Erlang functions.
  # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
  defp add_call_graph_edges_for_erlang_functions(call_graph) do
    call_graph
    |> CallGraph.add_edge({:erlang, :"=<", 2}, {:erlang, :<, 2})
    |> CallGraph.add_edge({:erlang, :"=<", 2}, {:erlang, :==, 2})
    |> CallGraph.add_edge({:erlang, :>=, 2}, {:erlang, :==, 2})
    |> CallGraph.add_edge({:erlang, :>=, 2}, {:erlang, :>, 2})
    |> CallGraph.add_edge({:erlang, :binary_to_atom, 1}, {:erlang, :binary_to_atom, 2})
    |> CallGraph.add_edge({:erlang, :binary_to_existing_atom, 1}, {:erlang, :binary_to_atom, 1})
    |> CallGraph.add_edge({:erlang, :binary_to_existing_atom, 2}, {:erlang, :binary_to_atom, 2})
    |> CallGraph.add_edge({:erlang, :error, 1}, {:erlang, :error, 2})
    |> CallGraph.add_edge({:erlang, :integer_to_binary, 1}, {:erlang, :integer_to_binary, 2})
    |> CallGraph.add_edge({:lists, :keymember, 3}, {:lists, :keyfind, 3})
    |> CallGraph.add_edge({:maps, :get, 2}, {:maps, :get, 3})
    |> CallGraph.add_edge(
      {:unicode, :characters_to_binary, 1},
      {:unicode, :characters_to_binary, 3}
    )
    |> CallGraph.add_edge({:unicode, :characters_to_binary, 3}, {:lists, :flatten, 1})
  end

  defp include_mfas_used_by_asset_path_registry_class(mfas) do
    mfas ++
      [
        {:maps, :get, 3},
        {:maps, :put, 3}
      ]
  end

  defp include_mfas_used_by_component_registry_class(mfas) do
    mfas ++
      [
        {:maps, :get, 2},
        {:maps, :get, 3}
      ]
  end

  defp include_mfas_used_by_interpreter_class(mfas) do
    mfas ++
      [
        {Enum, :into, 2},
        {Enum, :to_list, 1},
        {:erlang, :error, 1},
        {:erlang, :hd, 1},
        {:erlang, :tl, 1},
        {:lists, :keyfind, 3},
        {:maps, :get, 2}
      ]
  end

  defp include_mfas_used_by_manually_ported_code_module(mfas) do
    [{:code, :ensure_loaded, 1} | mfas]
  end

  defp include_mfas_used_by_operation_class(mfas) do
    mfas ++
      [
        {:maps, :from_list, 1},
        {:maps, :put, 3}
      ]
  end

  defp include_mfas_used_by_renderer_class(mfas) do
    mfas ++
      [
        {Hologram.Component, :__struct__, 0},
        {String.Chars, :to_string, 1},
        {:erlang, :binary_to_atom, 1},
        {:lists, :flatten, 1},
        {:maps, :from_list, 1},
        {:maps, :get, 2},
        {:maps, :merge, 2}
      ]
  end

  defp include_mfas_used_by_type_class(mfas) do
    [{:maps, :get, 3} | mfas]
  end

  defp include_mfas_used_frequently_on_the_client(mfas) do
    mfas ++
      [
        # Used by __props__/0 function injected into component and page modules.
        {Enum, :reverse, 1},
        {Hologram.Router.Helpers, :page_path, 1},
        {Hologram.Router.Helpers, :page_path, 2}
      ]
  end

  defp filter_elixir_mfas(mfas) do
    Enum.filter(mfas, fn {module, _function, _arity} -> Reflection.alias?(module) end)
  end

  defp filter_erlang_mfas(mfas) do
    Enum.filter(mfas, fn {module, _function, _arity} -> !Reflection.alias?(module) end)
  end

  # sobelow_skip ["CI.System"]
  defp format_entry_file(entry_file_path, opts) do
    cmd = [
      entry_file_path,
      "--config=#{opts[:js_formatter_config_path]}",
      # "none" is not a valid path or a flag value,
      # any non-existing path would work the same here, i.e. disable "ignore" functionality.
      "--ignore-path=none",
      "--no-error-on-unmatched-pattern",
      "--write"
    ]

    System.cmd(opts[:js_formatter_bin_path], cmd, env: [], parallelism: true)
  end

  defp mapset_from_plt(plt) do
    plt
    |> PLT.get_all()
    |> Map.keys()
    |> MapSet.new()
  end

  defp rebuild_ir_plt_entry(plt, module) do
    PLT.put(plt, module, IR.for_module(module))
  end

  defp rebuild_module_digest_plt_entry(plt, module) do
    data =
      module
      |> Reflection.module_beam_defs()
      |> :erlang.term_to_binary(compressed: 0)

    digest = CryptographicUtils.digest(data, :sha256, :binary)
    PLT.put(plt, module, digest)
  end

  defp remove_call_graph_vertices_of_manually_ported_elixir_functions(call_graph) do
    call_graph
    |> CallGraph.remove_vertex({Code, :ensure_loaded, 1})
    |> CallGraph.remove_vertex({Hologram.Router.Helpers, :asset_path, 1})
    |> CallGraph.remove_vertex({Kernel, :inspect, 1})
    |> CallGraph.remove_vertex({Kernel, :inspect, 2})
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
    |> Enum.reject(fn {module, _module_mfas} -> !BeamFile.exists?(module) end)
    |> Enum.sort()
    |> Enum.map_join("\n\n", fn {module, module_mfas} ->
      ir_plt
      |> PLT.get!(module)
      |> prune_module_def(module_mfas)
      |> Encoder.encode_ir(%Context{module: module})
    end)
  end

  defp render_erlang_function_defs(mfas, erlang_source_dir) do
    mfas
    |> filter_erlang_mfas()
    |> Enum.map_join("\n\n", fn {module, function, arity} ->
      Encoder.encode_erlang_function(module, function, arity, erlang_source_dir)
    end)
  end
end
