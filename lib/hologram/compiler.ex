defmodule Hologram.Compiler do
  alias Hologram.Commons.CryptographicUtils
  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection
  alias Hologram.Commons.StringUtils
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR

  @doc """
  Extracts JavaScript source code for the given ported Erlang function and generates interpreter function definition JavaScript statetement.
  """
  @spec build_erlang_function_definition(module, atom, integer, String.t()) :: String.t()
  def build_erlang_function_definition(module, function, arity, erlang_source_dir) do
    class = Encoder.encode_as_class_name(module)

    module
    |> Atom.to_string()
    |> StringUtils.append(".mjs")
    |> then(&Path.join(erlang_source_dir, &1))
    |> then(&{&1, File.exists?(&1)})
    |> then(fn
      {_file_path, false} -> nil
      {file_path, true} -> extract_erlang_function_source_code(file_path, function, arity)
    end)
    |> build(module, class, function, arity)
  end

  @spec build(nil, module, String.t(), atom, arity) :: String.t()
  defp build(nil, module, class, function, arity) do
    ~s/Interpreter.defineNotImplementedErlangFunction("#{module}", "#{class}", "#{function}", #{arity});/
  end

  @spec build(String.t(), module, String.t(), atom, arity) :: String.t()
  defp build(source_code, _module, class, function, arity) do
    ~s/Interpreter.defineErlangFunction("#{class}", "#{function}", #{arity}, #{source_code});/
  end

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
    erlang_source_dir = Path.join(source_dir, "erlang")
    function_defs = render_function_defs(mfas, erlang_source_dir, ir_plt)

    """
    "use strict";

    window.__hologramPageReachableFunctionDefs__ = (deps) => {
      const HologramBoxedError = deps.HologramBoxedError;
      const HologramInterpreterError = deps.HologramInterpreterError;
      const Interpreter = deps.Interpreter;
      const Type = deps.Type;#{function_defs}
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
    erlang_source_dir = Path.join(source_dir, "erlang")
    function_defs = render_function_defs(mfas, erlang_source_dir, ir_plt)

    """
    "use strict";

    import Hologram from "#{source_dir}/hologram.mjs";
    import HologramBoxedError from "#{source_dir}/errors/boxed_error.mjs";
    import HologramInterpreterError from "#{source_dir}/errors/interpreter_error.mjs";
    import Interpreter from "#{source_dir}/interpreter.mjs";
    import Type from "#{source_dir}/type.mjs";#{function_defs}

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

    entry_file = Path.join(tmp_dir, "#{entry_name}.entry.js")
    File.write!(entry_file, js)
    bundle_file = Path.join(bundle_dir, "#{bundle_name}.js")

    then(
      ~w[#{entry_file} --bundle --log-level=warning --minify --outfile=#{bundle_file} --sourcemap --target=es2020],
      &System.cmd(esbuild_path, &1, env: [])
    )

    digest =
      bundle_file
      |> File.read!()
      |> CryptographicUtils.digest(:md5, :hex)

    bundle_file_with_digest = Path.join("#{bundle_dir}", "#{bundle_name}-#{digest}.js")
    source_map_file_with_digest = bundle_file_with_digest <> ".map"

    File.rename!(bundle_file, bundle_file_with_digest)
    File.rename!(bundle_file <> ".map", source_map_file_with_digest)

    bundle_file_with_digest
    |> File.read!()
    |> String.replace(
      "//# sourceMappingURL=#{bundle_name}.js.map",
      "//# sourceMappingURL=#{bundle_name}-#{digest}.js.map"
    )
    |> tap(&File.write!(bundle_file_with_digest, &1))

    {digest, bundle_file_with_digest, source_map_file_with_digest}
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
  Installs JavaScript deps specified in package.json located in the given dir.
  """
  @spec install_js_deps(String.t()) :: :ok
  def install_js_deps(dir) do
    opts = [cd: dir, into: IO.stream(:stdio, :line)]

    # do not show unrelevant audit/fund/progress information during tests
    # leaving only warnings, errors and "up to date in Xs" message
    # alternatively --loglevel=silent or --silent (short version) could be used
    System.cmd("npm", ~w"install --loglevel=warn --no-audit --no-fund --no-progress", opts)
    :ok
  end

  @doc """
  Returns the list of MFAs that are reachable by the given page.
  MFAs required by the runtime are excluded.
  """
  @spec list_page_mfas(CallGraph.t(), module) :: list(mfa)
  def list_page_mfas(call_graph, page_module) do
    layout_module = page_module.__layout_module__()
    runtime_mfas = list_runtime_mfas(call_graph)

    call_graph
    |> CallGraph.clone()
    |> CallGraph.add_edge(page_module, {page_module, :__layout_module__, 0})
    |> CallGraph.add_edge(page_module, {page_module, :__layout_props__, 0})
    |> CallGraph.add_edge(page_module, {page_module, :action, 3})
    |> CallGraph.add_edge(page_module, {page_module, :template, 0})
    |> CallGraph.add_edge(page_module, {layout_module, :action, 3})
    |> CallGraph.add_edge(page_module, {layout_module, :template, 0})
    |> CallGraph.reachable(page_module)
    |> Enum.filter(&is_tuple/1)
    |> then(&(&1 -- runtime_mfas))
  end

  @doc """
  Groups the given MFAs by module.
  """
  @spec group_mfas_by_module(list(mfa)) :: %{module => mfa}
  def group_mfas_by_module(mfas) do
    Enum.group_by(mfas, fn {module, _function, _arity} -> module end)
  end

  @doc """
  Lists MFAs required by the runtime JS script.
  """
  @spec list_runtime_mfas(CallGraph.t()) :: list(mfa)
  def list_runtime_mfas(call_graph) do
    # These Elixir functions are used directly by the JS runtime:
    entry_mfas = [
      # Interpreter.comprehension()
      {Enum, :into, 2},

      # Interpreter.comprehension()
      {Enum, :to_list, 1},

      # Functions used both on the client and the server.
      {Hologram.Template.Renderer, :aggregate_vars, 2},
      {Hologram.Template.Renderer, :build_layout_props_dom, 2},

      # Interpreter.inspect()
      {Kernel, :inspect, 2},

      # Renderer.renderPage()
      {Map, :fetch!, 2},

      # Interpreter.raiseError()
      {:erlang, :error, 1},

      # Interpreter.#matchConsPattern()
      {:erlang, :hd, 1},

      # Interpreter.#matchConsPattern()
      {:erlang, :tl, 1},

      # Interpreter.dotOperator()
      {:maps, :get, 2}
    ]

    # Add call graph edges for Erlang functions depending on other Erlang functions.
    CallGraph.add_edge(call_graph, {:erlang, :"/=", 2}, {:erlang, :==, 2})
    CallGraph.add_edge(call_graph, {:erlang, :error, 1}, {:erlang, :error, 2})

    call_graph
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
  def prune_module_def(%{body: %{expressions: expressions}} = module_def_ir, reachable_mfas) do
    module = module_def_ir.module.value

    expressions
    |> Enum.filter(fn
      %IR.FunctionDefinition{name: function, arity: arity} ->
        reachable_mfas
        |> Enum.filter(fn {reachable_module, _function, _arity} -> reachable_module == module end)
        |> MapSet.new()
        |> MapSet.member?({module, function, arity})

      _fallback ->
        false
    end)
    |> then(&%IR.ModuleDefinition{module: module_def_ir.module, body: %IR.Block{expressions: &1}})
  end

  defp extract_erlang_function_source_code(file_path, function, arity) do
    key = "#{function}/#{arity}"
    start_marker = marker(key, "// start ")
    end_marker = marker(key, "// end ")
    file_contents = File.read!(file_path)

    ~r/#{start_marker}[[:space:]]+"#{Regex.escape(key)}":[[:space:]]+(.+),[[:space:]]+#{end_marker}/s
    |> Regex.run(file_contents)
    |> then(fn
      [_full_capture, source_code] -> source_code
      nil -> nil
    end)
  end

  @spec marker(String.t(), String.t()) :: String.t()
  defp marker(key, prefix) do
    key
    |> StringUtils.prepend(prefix)
    |> Regex.escape()
  end

  defp filter_elixir_mfas(mfas) do
    Enum.filter(mfas, &(not filter_erlang_mfa(&1)))
  end

  defp filter_erlang_mfas(mfas) do
    Enum.filter(mfas, &filter_erlang_mfa/1)
  end

  @spec filter_erlang_mfa(mfa) :: boolean
  defp filter_erlang_mfa({module, _function, _arity}) do
    not Reflection.alias?(module)
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
    module
    |> Reflection.module_beam_defs()
    |> :erlang.term_to_binary(compressed: 0)
    |> CryptographicUtils.digest(:sha256, :binary)
    |> then(&PLT.put(plt, module, &1))
  end

  defp render_block(str) do
    str
    |> String.trim()
    |> then(fn
      "" -> ""
      str -> StringUtils.prepend(str, "\n\n")
    end)
  end

  defp render_function_defs(mfas, erlang_source_dir, ir_plt) do
    erlang_function_defs = render_erlang_function_defs(mfas, erlang_source_dir)
    elixir_function_defs = render_elixir_function_defs(mfas, ir_plt)
    render_block(erlang_function_defs) <> render_block(elixir_function_defs)
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
      |> Encoder.encode(%Context{module: module})
    end)
  end

  defp render_erlang_function_defs(mfas, erlang_source_dir) do
    mfas
    |> filter_erlang_mfas()
    |> Enum.map_join("\n\n", fn {module, function, arity} ->
      build_erlang_function_definition(module, function, arity, erlang_source_dir)
    end)
  end
end
