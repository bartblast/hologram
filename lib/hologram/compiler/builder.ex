defmodule Hologram.Compiler.Builder do
  alias Hologram.Commons.CryptographicUtils
  alias Hologram.Commons.PLT
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR
  alias Hologram.Compiler.Reflection

  @doc """
  Builds JavaScript code for the given entry page.
  """
  @spec build_entry_page_js(CallGraph.t(), PLT.t(), module) :: String.t()
  # sobelow_skip ["DOS.BinToAtom"]
  def build_entry_page_js(call_graph, ir_plt, entry_page) do
    initial_output = """
    window.__hologramPageReachableFunctionDefs__ = (interpreterClass, typeClass) => {
      const Interpreter = interpreterClass;
      const Type = typeClass;\
    """

    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    clone_name = :"call_graph_#{__MODULE__}_#{entry_page}"

    call_graph
    |> entry_page_reachable_mfas(entry_page, clone_name)
    |> group_mfas_by_module()
    |> Enum.reduce([initial_output], fn {module, reachable_mfas}, output_parts ->
      module_output =
        ir_plt
        |> PLT.get!(module)
        |> prune_module_def(reachable_mfas)
        |> Encoder.encode(%Context{})

      [module_output | output_parts]
    end)
    |> List.insert_at(0, "\n\n}")
    |> Enum.reverse()
    |> Enum.join()
  end

  @doc """
  Builds a persistent lookup table (PLT) containing the BEAM defs digests for all the modules in the project.

  ## Examples

      iex> build_module_digest_plt(:abc)
      %PLT{pid: #PID<0.251.0>, name: :plt_abc}
  """
  @spec build_module_digest_plt(atom) :: PLT.t()
  def build_module_digest_plt(name) do
    plt = PLT.start(name: name)

    Reflection.list_loaded_otp_apps()
    |> Kernel.--([:hex])
    |> Reflection.list_elixir_modules()
    |> Task.async_stream(&rebuild_module_digest_plt_entry(plt, &1))
    |> Stream.run()

    plt
  end

  @doc """
  Builds Hologram runtime JS file and its source map.
  The generated filenames contain the hex digest of the built JS content.

  ## Examples

      iex> build_runtime_js("assets/node_modules/esbuild", "assets/js/hologram.mjs", "tmp")
      {"c4206fe5fa846da67e50ed03874ccbae",
       "tmp/hologram.runtime-c4206fe5fa846da67e50ed03874ccbae.js",
      "tmp/hologram.runtime-c4206fe5fa846da67e50ed03874ccbae.js.map"}
  """
  @spec build_runtime_js(String.t(), String.t(), String.t()) ::
          {String.t(), String.t(), String.t()}
  def build_runtime_js(esbuild_path, source_file, output_dir) do
    output_file = output_dir <> "/hologram.runtime.js"

    cmd = [
      esbuild_path,
      source_file,
      "--bundle",
      "--minify",
      "--outfile=#{output_file}",
      "--sourcemap",
      "--target=es2020"
    ]

    System.cmd("npx", cmd, env: [])

    digest =
      output_file
      |> File.read!()
      |> CryptographicUtils.digest(:md5, :hex)

    output_file_with_digest = output_dir <> "/hologram.runtime-#{digest}.js"

    source_map_file = output_file <> ".map"
    source_map_file_with_digest = output_file_with_digest <> ".map"

    File.rename!(output_file, output_file_with_digest)
    File.rename!(source_map_file, source_map_file_with_digest)

    js_with_replaced_source_map_url =
      output_file_with_digest
      |> File.read!()
      |> String.replace(
        "//# sourceMappingURL=hologram.runtime.js.map",
        "//# sourceMappingURL=hologram.runtime-#{digest}.js.map"
      )

    File.write!(output_file_with_digest, js_with_replaced_source_map_url)

    {digest, output_file_with_digest, source_map_file_with_digest}
  end

  @doc """
  Compares two module digest PLTs and returns the added, removed, and updated modules lists.

  ## Examples

      iex> old_plt = %PLT{pid: #PID<0.251.0>, name: :my_old_plt}
      iex> new_plt = %PLT{pid: #PID<0.259.0>, name: :my_new_plt}
      iex> diff_module_digest_plts(old_plt, new_plt)
      %{
        added_modules: [Module5, Module9],
        removed_modules: [Module1, Module3],
        updated_modules: [Module6, Module2]
      }
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
  Returns the list of mfas ({module, function, arity} tuples) that are reachable by the given entry page.

  ## Examples

      iex> call_graph = %CallGraph{name: :my_call_graph, pid: #PID<0.259.0>}
      iex> entry_page_reachable_mfas(call_graph, MyPage5, :my_call_graph_clone)
      [
        {MyPage5, :__hologram_layout_module__, 0},
        {MyPage5, :__hologram_layout_props__, 0},
        {MyPage5, :__hologram_route__, 0},
        {MyPage5, :action, 3},
        {MyPage5, :template, 0},
        {MyLayout, :action, 3},
        {MyLayout, :template, 0},
        {MyModule, :my_fun_7a, 2}
      ]
  """
  @spec entry_page_reachable_mfas(CallGraph.t(), module, atom) :: list(mfa)
  def entry_page_reachable_mfas(call_graph, entry_page, clone_name) do
    call_graph_clone = CallGraph.clone(call_graph, name: clone_name)
    layout_module = entry_page.__hologram_layout_module__()

    call_graph_clone
    |> CallGraph.add_edge(entry_page, {entry_page, :__hologram_layout_module__, 0})
    |> CallGraph.add_edge(entry_page, {entry_page, :__hologram_layout_props__, 0})
    |> CallGraph.add_edge(entry_page, {entry_page, :action, 3})
    |> CallGraph.add_edge(entry_page, {entry_page, :template, 0})
    |> CallGraph.add_edge(entry_page, {layout_module, :action, 3})
    |> CallGraph.add_edge(entry_page, {layout_module, :template, 0})
    |> CallGraph.reachable(entry_page)
    |> Enum.filter(&is_tuple/1)
  end

  @doc """
  Groups the given mfas by module.
  """
  @spec group_mfas_by_module(list(mfa)) :: %{module => mfa}
  def group_mfas_by_module(mfas) do
    Enum.group_by(mfas, fn {module, _function, _arity} -> module end)
  end

  @doc """
  Given a diff of changes, updates the IR persistent lookup table (PLT)
  by deleting entries for modules that have been removed,
  rebuilding the IR of modules that have been updated,
  and adding the IR of new modules.

  ## Examples

      iex> plt = %PLT{pid: #PID<0.251.0>, name: :plt_abc}
      iex> diff = %{
      ...>   added_modules: [Module1, Module2],
      ...>   removed_modules: [Module5, Module6],
      ...>   updated_modules: [Module3, Module4]
      ...> }
      iex> patch_ir_plt(plt, diff)
      %PLT{pid: #PID<0.251.0>, name: :plt_abc}
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
  Keeps in the body of module definition IR only those expressions that are function definitions of reachable functions.
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
    PLT.put(plt.name, module, digest)
  end
end
