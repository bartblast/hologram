# defmodule Hologram.Compiler do
#   alias Hologram.Commons.CryptographicUtils
#   alias Hologram.Commons.PLT
#   alias Hologram.Commons.Reflection
#   alias Hologram.Commons.TaskUtils
#   alias Hologram.Compiler.CallGraph
#   alias Hologram.Compiler.Context
#   alias Hologram.Compiler.Encoder
#   alias Hologram.Compiler.IR

#   @doc """
#   Builds a persistent lookup table (PLT) containing the BEAM defs digests for all the modules in the project.
#   """
#   @spec build_module_digest_plt(PLT.t()) :: PLT.t()
#   def build_module_digest_plt(module_beam_path_plt) do
#     module_digest_plt = PLT.start()

#     Reflection.list_elixir_modules()
#     |> TaskUtils.async_many(
#       &rebuild_module_digest_plt_entry(&1, module_digest_plt, module_beam_path_plt)
#     )
#     |> Task.await_many(:infinity)

#     module_digest_plt
#   end

#   @doc """
#   Builds JavaScript code for the given Hologram page.
#   """
#   @spec build_page_js(module, CallGraph.t(), PLT.t(), String.t()) :: String.t()
#   def build_page_js(page_module, call_graph, ir_plt, source_dir) do
#     mfas = list_page_mfas(call_graph, page_module)
#     erlang_source_dir = source_dir <> "/erlang"

#     erlang_function_defs =
#       mfas
#       |> render_erlang_function_defs(erlang_source_dir)
#       |> render_block()

#     elixir_function_defs =
#       mfas
#       |> render_elixir_function_defs(ir_plt)
#       |> render_block()

#     """
#     "use strict";

#     window.__hologramPageReachableFunctionDefs__ = (deps) => {
#       const {
#         Bitstring,
#         HologramBoxedError,
#         HologramInterpreterError,
#         Interpreter,
#         MemoryStorage,
#         Type,
#         Utils,
#       } = deps;#{erlang_function_defs}#{elixir_function_defs}
#     }

#     window.__hologramPageScriptLoaded__ = true;
#     document.dispatchEvent(new CustomEvent("hologram:pageScriptLoaded"));\
#     """
#   end

#   @doc """
#   Builds Hologram runtime JavaScript source code.
#   """
#   @spec build_runtime_js(String.t(), CallGraph.t(), PLT.t()) :: String.t()
#   def build_runtime_js(source_dir, call_graph, ir_plt) do
#     mfas = list_runtime_mfas(call_graph)

#     erlang_function_defs =
#       mfas
#       |> render_erlang_function_defs("#{source_dir}/erlang")
#       |> render_block()

#     elixir_function_defs =
#       mfas
#       |> render_elixir_function_defs(ir_plt)
#       |> render_block()

#     """
#     "use strict";

#     import Bitstring from "#{source_dir}/bitstring.mjs";
#     import Hologram from "#{source_dir}/hologram.mjs";
#     import HologramBoxedError from "#{source_dir}/errors/boxed_error.mjs";
#     import HologramInterpreterError from "#{source_dir}/errors/interpreter_error.mjs";
#     import Interpreter from "#{source_dir}/interpreter.mjs";
#     import MemoryStorage from "#{source_dir}/memory_storage.mjs";
#     import Type from "#{source_dir}/type.mjs";
#     import Utils from "#{source_dir}/utils.mjs";#{erlang_function_defs}#{elixir_function_defs}

#     document.addEventListener("hologram:pageScriptLoaded", () => Hologram.run());

#     if (window.__hologramPageScriptLoaded__) {
#       document.dispatchEvent(new CustomEvent("hologram:pageScriptLoaded"));
#     }\
#     """
#   end

#   @doc """
#   Bundles the given JavaScript code into a JavaScript file and its source map.
#   The generated file names contain the hex digest of the bundled JavaScript file content.

#   ## Examples

#       iex> bundle(js, opts)
#       {"caf8f4e27584852044eb27a37c5eddfd",
#        "priv/static/my_script-caf8f4e27584852044eb27a37c5eddfd.js",
#        "priv/static/my_script-caf8f4e27584852044eb27a37c5eddfd.js.map"}
#   """
#   @spec bundle(term, String.t(), keyword) :: {String.t(), String.t(), String.t()}
#   # sobelow_skip ["CI.System"]
#   def bundle(entry_name, entry_file_path, opts) do
#     bundle_name = opts[:bundle_name]
#     esbuild_path = opts[:esbuild_path]
#     static_dir = opts[:static_dir]
#     tmp_dir = opts[:tmp_dir]

#     File.mkdir_p!(static_dir)

#     output_bundle_path = tmp_dir <> "/#{entry_name}.output.js"

#     esbuild_cmd = [
#       entry_file_path,
#       "--bundle",
#       "--log-level=warning",
#       "--minify",
#       "--outfile=#{output_bundle_path}",
#       "--sourcemap",
#       "--target=es2020"
#     ]

#     System.cmd(esbuild_path, esbuild_cmd, env: [], parallelism: true)

#     digest =
#       output_bundle_path
#       |> File.read!()
#       |> CryptographicUtils.digest(:md5, :hex)

#     static_bundle_path_with_digest = "#{static_dir}/#{bundle_name}-#{digest}.js"

#     output_source_map_path = output_bundle_path <> ".map"
#     static_source_map_path_with_digest = static_bundle_path_with_digest <> ".map"

#     File.rename!(output_bundle_path, static_bundle_path_with_digest)
#     File.rename!(output_source_map_path, static_source_map_path_with_digest)

#     js_with_replaced_source_map_url =
#       static_bundle_path_with_digest
#       |> File.read!()
#       |> String.replace(
#         "//# sourceMappingURL=#{entry_name}.output.js.map",
#         "//# sourceMappingURL=#{bundle_name}-#{digest}.js.map"
#       )

#     File.write!(static_bundle_path_with_digest, js_with_replaced_source_map_url)

#     {entry_name, digest}
#   end

#   def create_entry_file(js, entry_name, tmp_dir) do
#     File.mkdir_p!(tmp_dir)

#     entry_file_path = Path.join(tmp_dir, "#{entry_name}.entry.js")
#     File.write!(entry_file_path, js)

#     entry_file_path
#   end

#   @doc """
#   Compares two module digest PLTs and returns the added, removed, and updated modules lists.
#   """
#   @spec diff_module_digest_plts(PLT.t(), PLT.t()) :: %{
#           added_modules: list,
#           removed_modules: list,
#           updated_modules: list
#         }
#   def diff_module_digest_plts(old_plt, new_plt) do
#     old_mapset = mapset_from_plt(old_plt)
#     new_mapset = mapset_from_plt(new_plt)

#     removed_modules =
#       old_mapset
#       |> MapSet.difference(new_mapset)
#       |> MapSet.to_list()

#     added_modules =
#       new_mapset
#       |> MapSet.difference(old_mapset)
#       |> MapSet.to_list()

#     updated_modules =
#       old_mapset
#       |> MapSet.intersection(new_mapset)
#       |> MapSet.to_list()
#       |> Enum.filter(&(PLT.get(old_plt, &1) != PLT.get(new_plt, &1)))

#     %{
#       added_modules: added_modules,
#       removed_modules: removed_modules,
#       updated_modules: updated_modules
#     }
#   end

#   @doc """
#   Groups the given MFAs by module.
#   """
#   @spec group_mfas_by_module(list(mfa)) :: %{module => mfa}
#   def group_mfas_by_module(mfas) do
#     Enum.group_by(mfas, fn {module, _function, _arity} -> module end)
#   end

#   @doc """
#   Installs JavaScript deps specified in package.json in :assets_source_dir to :build_dir.
#   Saves the package.json digest to package_json_digest.bin file.
#   """
#   @spec install_js_deps(keyword) :: :ok
#   def install_js_deps(opts) do
#     cmd_opts = [cd: opts[:assets_source_dir], into: IO.stream(:stdio, :line)]
#     System.cmd("npm", ["install", "--silent", "--no-progress"], cmd_opts)

#     package_json_digest_path = Path.join(opts[:build_dir], "package_json_digest.bin")
#     package_json_digest = get_package_json_digest(opts[:assets_source_dir])

#     package_json_digest_path
#     |> Path.dirname()
#     |> File.mkdir_p!()

#     File.write!(package_json_digest_path, package_json_digest)
#   end

#   @doc """
#   Returns the list of MFAs that are reachable by the given page.
#   Functions required by the runtime as well as manually ported Elixir functions are excluded.
#   """
#   @spec list_page_mfas(CallGraph.t(), module) :: list(mfa)
#   def list_page_mfas(call_graph, page_module) do
#     layout_module = page_module.__layout_module__()
#     runtime_mfas = list_runtime_mfas(call_graph)

#     call_graph
#     |> CallGraph.get_graph()
#     |> Graph.add_edge(page_module, {page_module, :__layout_module__, 0})
#     |> Graph.add_edge(page_module, {page_module, :__layout_props__, 0})
#     |> Graph.add_edge(page_module, {page_module, :__props__, 0})
#     |> Graph.add_edge(page_module, {page_module, :action, 3})
#     |> Graph.add_edge(page_module, {page_module, :template, 0})
#     |> Graph.add_edge(page_module, {layout_module, :__props__, 0})
#     |> Graph.add_edge(page_module, {layout_module, :action, 3})
#     |> Graph.add_edge(page_module, {layout_module, :template, 0})
#     |> remove_call_graph_vertices_of_manually_ported_elixir_functions()
#     |> CallGraph.reachable(page_module)
#     |> Enum.filter(&is_tuple/1)
#     |> Kernel.--(runtime_mfas)
#   end

#   @doc """
#   Lists MFAs required by the runtime JS script.
#   Manually ported Elixir functions are excluded.
#   """
#   @spec list_runtime_mfas(CallGraph.t()) :: list(mfa)
#   def list_runtime_mfas(call_graph) do
#     entry_mfas =
#       []
#       |> include_mfas_used_by_asset_path_registry_class()
#       |> include_mfas_used_by_component_registry_class()
#       |> include_mfas_used_frequently_on_the_client()
#       |> include_mfas_used_by_interpreter_class()
#       |> include_mfas_used_by_manually_ported_code_module()
#       |> include_mfas_used_by_operation_class()
#       |> include_mfas_used_by_renderer_class()
#       |> include_mfas_used_by_type_class()
#       |> Enum.uniq()

#     call_graph
#     |> CallGraph.get_graph()
#     |> add_call_graph_edges_for_erlang_functions()
#     |> remove_call_graph_vertices_of_manually_ported_elixir_functions()
#     |> CallGraph.reachable_mfas(entry_mfas)
#     # Some protocol implementations are referenced but not actually implemented, e.g. Collectable.Atom
#     |> Enum.reject(fn {module, _function, _arity} -> !Reflection.module?(module) end)
#     |> Enum.uniq()
#     |> Enum.sort()
#   end

#   @doc """
#   Installs JavaScript deps if package.json has changed or if the deps haven't been installed yet.
#   """
#   @spec maybe_install_js_deps(keyword) :: :ok | nil
#   def maybe_install_js_deps(opts) do
#     package_json_digest_path = Path.join(opts[:build_dir], "package_json_digest.bin")
#     package_json_lock_path = Path.join(opts[:assets_source_dir], "package-lock.json")

#     if !File.exists?(package_json_digest_path) or !File.exists?(package_json_lock_path) do
#       install_js_deps(opts)
#     else
#       old_package_json_digest = File.read!(package_json_digest_path)
#       new_package_json_digest = get_package_json_digest(opts[:assets_source_dir])

#       if new_package_json_digest != old_package_json_digest do
#         install_js_deps(opts)
#       end
#     end
#   end

#   @doc """
#   Given a diff of changes, updates the IR persistent lookup table (PLT)
#   by deleting entries for modules that have been removed,
#   rebuilding the IR of modules that have been updated,
#   and adding the IR of new modules.
#   """
#   @spec patch_ir_plt(PLT.t(), map, PLT.t()) :: PLT.t()
#   def patch_ir_plt(ir_plt, diff, module_beam_path_plt) do
#     delete_tasks = TaskUtils.async_many(diff.removed_modules, &PLT.delete(ir_plt, &1))

#     rebuild_tasks =
#       TaskUtils.async_many(
#         diff.updated_modules ++ diff.added_modules,
#         &rebuild_ir_plt_entry(ir_plt, &1, module_beam_path_plt)
#       )

#     Task.await_many(delete_tasks, :infinity)
#     Task.await_many(rebuild_tasks, :infinity)

#     ir_plt
#   end

#   @doc """
#   Keeps only those IR expressions that are function definitions of the given reachable MFAs.
#   """
#   @spec prune_module_def(IR.ModuleDefinition.t(), list(mfa)) :: IR.ModuleDefinition.t()
#   def prune_module_def(module_def_ir, reachable_mfas) do
#     module = module_def_ir.module.value

#     module_reachable_mfas =
#       reachable_mfas
#       |> Enum.filter(fn {reachable_module, _function, _arity} -> reachable_module == module end)
#       |> MapSet.new()

#     function_defs =
#       Enum.filter(module_def_ir.body.expressions, fn
#         %IR.FunctionDefinition{name: function, arity: arity} ->
#           MapSet.member?(module_reachable_mfas, {module, function, arity})

#         _fallback ->
#           false
#       end)

#     %IR.ModuleDefinition{
#       module: module_def_ir.module,
#       body: %IR.Block{expressions: function_defs}
#     }
#   end

#   # Add call graph edges for Erlang functions depending on other Erlang functions.
#   # credo:disable-for-next-line Credo.Check.Refactor.ABCSize
#   defp add_call_graph_edges_for_erlang_functions(graph) do
#     Graph.add_edges(graph, [
#       {{:erlang, :"=<", 2}, {:erlang, :<, 2}},
#       {{:erlang, :"=<", 2}, {:erlang, :==, 2}},
#       {{:erlang, :>=, 2}, {:erlang, :==, 2}},
#       {{:erlang, :>=, 2}, {:erlang, :>, 2}},
#       {{:erlang, :binary_to_atom, 1}, {:erlang, :binary_to_atom, 2}},
#       {{:erlang, :binary_to_existing_atom, 1}, {:erlang, :binary_to_atom, 1}},
#       {{:erlang, :binary_to_existing_atom, 2}, {:erlang, :binary_to_atom, 2}},
#       {{:erlang, :error, 1}, {:erlang, :error, 2}},
#       {{:erlang, :integer_to_binary, 1}, {:erlang, :integer_to_binary, 2}},
#       {{:lists, :keymember, 3}, {:lists, :keyfind, 3}},
#       {{:maps, :get, 2}, {:maps, :get, 3}},
#       {{:unicode, :characters_to_binary, 1}, {:unicode, :characters_to_binary, 3}},
#       {{:unicode, :characters_to_binary, 3}, {:lists, :flatten, 1}}
#     ])
#   end

#   defp get_package_json_digest(assets_source_dir) do
#     assets_source_dir
#     |> Path.join("package.json")
#     |> File.read!()
#     |> CryptographicUtils.digest(:sha256, :binary)
#   end

#   defp include_mfas_used_by_asset_path_registry_class(mfas) do
#     [
#       {:maps, :get, 3},
#       {:maps, :put, 3} | mfas
#     ]
#   end

#   defp include_mfas_used_by_component_registry_class(mfas) do
#     [
#       {:maps, :get, 2},
#       {:maps, :get, 3} | mfas
#     ]
#   end

#   defp include_mfas_used_by_interpreter_class(mfas) do
#     [
#       {Enum, :into, 2},
#       {Enum, :to_list, 1},
#       {:erlang, :error, 1},
#       {:erlang, :hd, 1},
#       {:erlang, :tl, 1},
#       {:lists, :keyfind, 3},
#       {:maps, :get, 2} | mfas
#     ]
#   end

#   defp include_mfas_used_by_manually_ported_code_module(mfas) do
#     [{:code, :ensure_loaded, 1} | mfas]
#   end

#   defp include_mfas_used_by_operation_class(mfas) do
#     [
#       {:maps, :from_list, 1},
#       {:maps, :put, 3} | mfas
#     ]
#   end

#   defp include_mfas_used_by_renderer_class(mfas) do
#     [
#       {Hologram.Component, :__struct__, 0},
#       {String.Chars, :to_string, 1},
#       {:erlang, :binary_to_atom, 1},
#       {:lists, :flatten, 1},
#       {:maps, :from_list, 1},
#       {:maps, :get, 2},
#       {:maps, :merge, 2} | mfas
#     ]
#   end

#   defp include_mfas_used_by_type_class(mfas) do
#     [{:maps, :get, 3} | mfas]
#   end

#   defp include_mfas_used_frequently_on_the_client(mfas) do
#     [
#       # Used by __props__/0 function injected into component and page modules.
#       {Enum, :reverse, 1},
#       {Hologram.Router.Helpers, :page_path, 1},
#       {Hologram.Router.Helpers, :page_path, 2} | mfas
#     ]
#   end

#   defp filter_elixir_mfas(mfas) do
#     Enum.filter(mfas, fn {module, _function, _arity} -> Reflection.alias?(module) end)
#   end

#   defp filter_erlang_mfas(mfas) do
#     Enum.filter(mfas, fn {module, _function, _arity} -> !Reflection.alias?(module) end)
#   end

#   defp mapset_from_plt(plt) do
#     plt
#     |> PLT.get_all()
#     |> Map.keys()
#     |> MapSet.new()
#   end

#   defp rebuild_ir_plt_entry(plt, module, module_beam_path_plt) do
#     beam_path = PLT.get!(module_beam_path_plt, module)
#     PLT.put(plt, module, IR.for_module(beam_path))
#   end

#   defp rebuild_module_digest_plt_entry(module, module_digest_plt, module_beam_path_plt) do
#     module_beam_path =
#       case PLT.get(module_beam_path_plt, module) do
#         {:ok, path} ->
#           path

#         :error ->
#           path = :code.which(module)
#           PLT.put(module_beam_path_plt, module, path)
#           path
#       end

#     data =
#       module_beam_path
#       |> Reflection.beam_defs()
#       |> :erlang.term_to_binary(compressed: 0)

#     digest = CryptographicUtils.digest(data, :sha256, :binary)
#     PLT.put(module_digest_plt, module, digest)
#   end

#   defp remove_call_graph_vertices_of_manually_ported_elixir_functions(graph) do
#     Graph.delete_vertices(graph, [
#       {Code, :ensure_loaded, 1},
#       {Hologram.Router.Helpers, :asset_path, 1},
#       {Kernel, :inspect, 1},
#       {Kernel, :inspect, 2}
#     ])
#   end

#   defp render_block(str) do
#     str = String.trim(str)

#     if str != "" do
#       "\n\n" <> str
#     else
#       ""
#     end
#   end

#   defp render_elixir_function_defs(mfas, ir_plt) do
#     mfas
#     |> filter_elixir_mfas()
#     |> group_mfas_by_module()
#     |> Enum.sort()
#     |> Enum.map_join("\n\n", fn {module, module_mfas} ->
#       ir_plt
#       |> PLT.get!(module)
#       |> prune_module_def(module_mfas)
#       |> Encoder.encode_ir(%Context{module: module})
#     end)
#   end

#   defp render_erlang_function_defs(mfas, erlang_source_dir) do
#     mfas
#     |> filter_erlang_mfas()
#     |> Enum.map_join("\n\n", fn {module, function, arity} ->
#       Encoder.encode_erlang_function(module, function, arity, erlang_source_dir)
#     end)
#   end
# end
