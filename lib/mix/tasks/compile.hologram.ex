defmodule Mix.Tasks.Compile.Hologram do
  @moduledoc """
  Builds Hologram runtime and page JavaScript files for the current project.
  """

  use Mix.Task.Compiler

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.Builder
  alias Hologram.Compiler.CallGraph
  alias Hologram.Compiler.Reflection

  @env Application.compile_env!(:hologram, :env)
  @root_path Reflection.root_path()

  @build_dir "#{@root_path}/_build/#{@env}/lib/hologram/priv"
  @bundle_dir "#{@root_path}/priv/static/assets"
  @esbuild_path "#{@root_path}/deps/hologram/assets/node_modules/.bin/esbuild"
  @js_source_dir "#{@root_path}/deps/hologram/assets/js"

  @default_opts [
    build_dir: @build_dir,
    bundle_dir: @bundle_dir,
    esbuild_path: @esbuild_path,
    js_source_dir: @js_source_dir
  ]

  @doc false
  @impl Mix.Task.Compiler
  def run(opts \\ @default_opts) do
    new_module_digest_plt = Builder.build_module_digest_plt()
    old_module_digest_plt = PLT.start()
    module_digest_plt_dump_path = opts[:build_dir] <> "/module_digest.plt"
    PLT.maybe_load(old_module_digest_plt, module_digest_plt_dump_path)

    diff = Builder.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)

    ir_plt = PLT.start()
    ir_plt_dump_path = opts[:build_dir] <> "/ir.plt"
    PLT.maybe_load(ir_plt_dump_path, ir_plt_dump_path)
    Builder.patch_ir_plt(ir_plt, diff)

    call_graph = CallGraph.start()
    call_graph_dump_path = opts[:build_dir] <> "/call_graph.bin"
    CallGraph.maybe_load(call_graph, call_graph_dump_path)
    CallGraph.patch(call_graph, ir_plt, diff)

    opts[:js_source_dir]
    |> Builder.build_runtime_js(call_graph, ir_plt)
    |> Builder.bundle(
      "hologram.runtime",
      opts[:esbuild_path],
      opts[:build_dir],
      opts[:bundle_dir]
    )

    # TODO: bundle runtime and pages
    # Reflections.list_pages()
    # |> Builder.build_page_js(&1, output_path, module_defs, call_graph))
    # |> patch page digest plt
    # |> create page-digest files

    # dump PLTs and call graph...
    # PLT.dump(ir_plt)
    # PLT.dump(new_module_digest_plt)

    :ok
  end
end
