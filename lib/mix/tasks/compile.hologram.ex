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

    {module_beam_path_plt, module_beam_path_plt_dump_path} =
      Compiler.maybe_load_module_beam_path_plt(build_dir)

    new_module_digest_plt = Compiler.build_module_digest_plt(module_beam_path_plt)

    {old_module_digest_plt, module_digest_plt_dump_path} =
      Compiler.maybe_load_module_digest_plt(build_dir)

    module_digests_diff =
      Compiler.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)

    {ir_plt, ir_plt_dump_path} = Compiler.maybe_load_ir_plt(build_dir)
    Compiler.patch_ir_plt(ir_plt, module_digests_diff, module_beam_path_plt)

    {call_graph, call_graph_dump_path} = Compiler.maybe_load_call_graph(build_dir)
    CallGraph.patch(call_graph, ir_plt, module_digests_diff)

    Compiler.maybe_install_js_deps(assets_dir, build_dir)

    CallGraph.dump(call_graph, call_graph_dump_path)
    PLT.dump(ir_plt, ir_plt_dump_path)
    PLT.dump(new_module_digest_plt, module_digest_plt_dump_path)
    PLT.dump(module_beam_path_plt, module_beam_path_plt_dump_path)

    Logger.info("Hologram: compiler finished")

    :ok
  end
end

# # credo:disable-for-this-file Credo.Check.Refactor.ABCSize
# defmodule Mix.Tasks.Compile.Hologram do
#   alias Hologram.Commons.TaskUtils

#   def compile(opts) do
#     runtime_entry_file_path = create_runtime_entry_file(call_graph, ir_plt, opts)

#     page_modules = Reflection.list_pages()

#     validate_page_modules(page_modules)

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

#   defp validate_page_modules(page_modules) do
#     Enum.each(page_modules, fn page_module ->
#       if !Reflection.has_function?(page_module, :__route__, 0) do
#         raise Hologram.CompileError,
#           message:
#             "Page '#{page_module}' doesn't have a route specified (use the route/1 macro to fix the issue)."
#       end

#       if !Reflection.has_function?(page_module, :__layout_module__, 0) do
#         raise Hologram.CompileError,
#           message:
#             "Page '#{page_module}' doesn't have a layout module specified (use the layout/1 macro to fix the issue)."
#       end
#     end)
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

#   defp create_runtime_entry_file(call_graph, ir_plt, opts) do
#     opts[:js_source_dir]
#     |> Compiler.build_runtime_js(call_graph, ir_plt)
#     |> Compiler.create_entry_file("runtime", opts[:tmp_dir])
#   end

#   defp maybe_load_module_beam_path_plt(opts) do
#     module_beam_path_plt = PLT.start()
#     module_beam_path_plt_dump_path = opts[:build_dir] <> "/module_beam_path.plt"
#     PLT.maybe_load(module_beam_path_plt, module_beam_path_plt_dump_path)

#     {module_beam_path_plt, module_beam_path_plt_dump_path}
#   end
# end
