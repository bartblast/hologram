# TODO: finish & test

defmodule Mix.Tasks.Compile.Hologram do
  @moduledoc """
  Builds JavaScript files for the current project.

  ## Examples

      $ mix compile.hologram
  """

  use Mix.Task.Compiler

  alias Hologram.Commons.PersistentLookupTable, as: PLT
  alias Hologram.Compiler.Builder
  alias Hologram.Compiler.Reflection

  # @call_graph_dump_path Reflection.root_priv_path() <> "/call_graph.bin"
  # @call_graph_name :hologram_call_graph

  @ir_plt_dump_path Reflection.root_priv_path() <> "/plt_ir.bin"
  @ir_plt_name :hologram_plt_ir

  @module_digest_plt_dump_path Reflection.root_priv_path() <> "/plt_module_digest.bin"
  @module_digest_plt_name :hologram_plt_module_digest

  @doc false
  @impl Mix.Task.Compiler
  def run(_opts \\ []) do
    new_module_digest_plt = Builder.build_module_digest_plt()

    old_module_digest_plt =
      PLT.start(name: @module_digest_plt_name, dump_path: @module_digest_plt_dump_path)

    diff = Builder.diff_module_digest_plts(old_module_digest_plt, new_module_digest_plt)

    ir_plt = PLT.start(name: @ir_plt_name, dump_path: @ir_plt_dump_path)
    Builder.patch_ir_plt(ir_plt, diff)

    # call_graph = CallGraph.start(name: @call_graph_name, dump_path: @call_graph_dump_path)
    # CallGraph.patch(call_graph, diff)

    # Reflections.list_pages()
    # |> Builder.build_page_js(&1, output_path, module_defs, call_graph))
    # |> patch page digest plt
    # |> create page-digest files

    # write PLTs and call graph...

    :ok
  end
end
