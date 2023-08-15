# TODO: finish & test

defmodule Mix.Tasks.Compile.Hologram do
  @moduledoc """
  Builds JavaScript files for the current project.

  ## Examples

      $ mix compile.hologram
  """

  use Mix.Task.Compiler

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.Builder
  alias Hologram.Compiler.CallGraph
  # alias Hologram.Compiler.Reflection

  # @call_graph_dump_path Reflection.root_priv_path() <> "/call_graph.bin"
  # @ir_plt_dump_path Reflection.root_priv_path() <> "/plt_ir.bin"
  # @module_digest_plt_dump_path Reflection.root_priv_path() <> "/plt_module_digest.bin"

  @doc false
  @impl Mix.Task.Compiler
  def run(_opts \\ []) do
    new_module_digest_plt = Builder.build_module_digest_plt()

    # TODO: maybe load from dump
    old_module_digest_plt = PLT.start()

    diff = Builder.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)

    # TODO: maybe load from dump
    ir_plt = PLT.start()
    Builder.patch_ir_plt(ir_plt, diff)

    # TODO: maybe load from dump
    call_graph = CallGraph.start()
    CallGraph.patch(call_graph, ir_plt, diff)

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
