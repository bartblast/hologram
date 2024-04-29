defmodule Mix.Tasks.Compile.Hologram do
  @moduledoc """
  Builds Hologram project JavaScript bundles, the call graph of the code,
  PLTs needed by the runtime and PLTs needed to speed up future compilation.
  """

  use Mix.Task.Compiler

  alias Hologram.Commons.PLT
  alias Hologram.Commons.Reflection
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph

  require Logger

  @impl Mix.Task.Compiler
  def run([]) do
    root_dir = Reflection.root_dir()
    assets_dir = Path.join([root_dir, "deps", "hologram", "assets"])
    build_dir = Reflection.build_dir()
    node_modules_path = Path.join(assets_dir, "node_modules")

    opts = [
      assets_dir: assets_dir,
      build_dir: build_dir,
      esbuild_bin_path: Path.join([node_modules_path, ".bin", "esbuild"]),
      formatter_bin_path: Path.join([node_modules_path, ".bin", "prettier"]),
      formatter_config_path: Path.join(assets_dir, ".prettierrc.json"),
      js_dir: Path.join(assets_dir, "js"),
      static_dir: Path.join([root_dir, "priv", "static", "hologram"]),
      tmp_dir: Path.join(build_dir, "tmp")
    ]

    run(opts)
  end

  @impl Mix.Task.Compiler
  def run(opts) do
    Logger.info("Hologram: compiler started")

    assets_dir = opts[:assets_dir]
    build_dir = opts[:build_dir]

    File.mkdir_p!(build_dir)
    File.mkdir_p!(opts[:static_dir])
    File.mkdir_p!(opts[:tmp_dir])

    Compiler.maybe_install_js_deps(assets_dir, build_dir)

    {module_beam_path_plt, module_beam_path_plt_dump_path} =
      Compiler.maybe_load_module_beam_path_plt(build_dir)

    # Building IR PLT from scratch is almost x2 faster than loading IR PLT from a dump file,
    # so Compiler.build_ir_plt/1 is used instead of Compiler.maybe_load_ir_plt/1 + Compiler.patch_ir_plt!/3.
    ir_plt = Compiler.build_ir_plt(module_beam_path_plt)

    # Patching call graph for 1 updated module takes ~100-400 ms, so it's too long if there are multiple updates
    # (and one needs to take into account that the graph has to be loaded first and dumped at the end).
    # Building call graph from scratch is more predictable as it takes ~563 ms for ~1300 modules.
    call_graph =
      ir_plt
      |> Compiler.build_call_graph()
      # DEFER: In case the list of manually ported MFAs grows to ~32 vertices,
      # consider using similar strategy to CallGraph.remove_runtime_mfas/2,
      # e.g. implement opts param for CallGraph.remove_vertices/2 to allow rebuilding the graph.
      |> CallGraph.remove_manually_ported_mfas()

    runtime_mfas = CallGraph.list_runtime_mfas(call_graph)

    _runtime_entry_file_path = Compiler.create_runtime_entry_file(runtime_mfas, ir_plt, opts)

    page_modules = Reflection.list_pages()

    Compiler.validate_page_modules(page_modules)

    PLT.dump(module_beam_path_plt, module_beam_path_plt_dump_path)

    Logger.info("Hologram: compiler finished")

    :ok
  end
end

# # credo:disable-for-this-file Credo.Check.Refactor.ABCSize
# defmodule Mix.Tasks.Compile.Hologram do
#   alias Hologram.Commons.TaskUtils

#   def compile(opts) do
#     TODO: remove runtime mfas from call graph before using it for pages

#     page_entry_files_info =
#       create_page_entry_files(page_modules, call_graph, ir_plt, opts[:js_source_dir])

#     page_entry_file_paths =
#       Enum.map(page_entry_files_info, fn {_entry_name, entry_file_path} -> entry_file_path end)

#     format_files([runtime_entry_file_path | page_entry_file_paths], opts)

#     entry_files_info = [{"runtime", runtime_entry_file_path} | page_entry_files_info]

#     bundle_info = bundle_entry_files(entry_files_info, opts)

#     Logger.debug("Hologram: finished runtime & pages bundling")

#     {page_digest_plt, page_digest_plt_dump_path} = build_page_digest_plt(bundle_info, opts)

#     PLT.dump(page_digest_plt, page_digest_plt_dump_path)

#     :ok
#   end

#   defp build_page_digest_plt(bundle_info, opts) do
#     page_digest_plt = PLT.start()

#     bundle_info
#     |> Enum.reject(fn {entry_name, _digest} -> entry_name == "runtime" end)
#     |> Enum.each(fn {page_module, digest} -> PLT.put(page_digest_plt, page_module, digest) end)

#     page_digest_plt_dump_path =
#       Path.join([opts[:build_dir], Reflection.page_digest_plt_dump_file_name()])

#     {page_digest_plt, page_digest_plt_dump_path}
#   end

#   defp bundle_entry_files(entry_files_info, opts) do
#     entry_files_info
#     |> TaskUtils.async_many(fn {entry_name, entry_file_path} ->
#       Compiler.bundle(entry_name, entry_file_path, opts)
#     end)
#     |> Task.await_many(:infinity)
#   end

#   # sobelow_skip ["CI.System"]
#   defp format_files(file_paths, opts) do
#     cmd =
#       file_paths ++
#         [
#           "--config=#{opts[:js_formatter_config_path]}",
#           # "none" is not a valid path or a flag value,
#           # any non-existing path would work the same here, i.e. disable "ignore" functionality.
#           "--ignore-path=none",
#           "--no-error-on-unmatched-pattern",
#           "--write"
#         ]

#     System.cmd(opts[:js_formatter_bin_path], cmd, env: [], parallelism: true)
#   end

#   defp create_page_entry_files(page_modules, call_graph, ir_plt, js_source_dir) do
#     page_modules
#     |> TaskUtils.async_many(fn page_module ->
#       entry_file_path =
#         page_module
#         |> Compiler.build_page_js(call_graph, ir_plt, js_source_dir)
#         |> Compiler.create_entry_file(page_module, js_source_dir)

#       {page_module, entry_file_path}
#     end)
#     |> Task.await_many(:infinity)
#   end

#   defp maybe_load_module_beam_path_plt(opts) do
#     module_beam_path_plt = PLT.start()
#     module_beam_path_plt_dump_path = opts[:build_dir] <> "/module_beam_path.plt"
#     PLT.maybe_load(module_beam_path_plt, module_beam_path_plt_dump_path)

#     {module_beam_path_plt, module_beam_path_plt_dump_path}
#   end
# end
