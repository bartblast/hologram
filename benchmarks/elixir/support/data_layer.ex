defmodule Hologram.Benchmarks.DataLayer do
  @moduledoc false

  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Reflection

  @doc """
  Returns what the data layer folds its outputs from, for every page of the build, derived the way
  a cold compile derives it: what the data layer keeps of each page's reach, and the module info
  PLT the entity types are told by.
  """
  @spec kept_inputs() :: {%{module => Compiler.kept_page_reach()}, PLT.t()}
  def kept_inputs do
    ir_plt = Compiler.build_ir_plt()
    call_graph = Compiler.build_call_graph(ir_plt)
    module_info_plt = CallGraph.module_info_plt(call_graph)
    page_modules = Reflection.list_pages()

    # Asked before remove_manually_ported_mfas/1: the permission checks are manually ported, so
    # the graph the reach below is listed on no longer holds the vertices to ask about.
    permission_checking_pages =
      page_modules
      |> Compiler.list_reach_by_page(call_graph)
      |> Compiler.pages_checking_permissions()

    unsplit_call_graph = CallGraph.clone(call_graph)

    CallGraph.remove_manually_ported_mfas(call_graph)

    # Listed with the runtime's MFAs still in the graph, as the compile task lists it: a
    # component reached through a runtime MFA is still one the page can reach.
    listed_reach =
      page_modules
      |> Compiler.list_reach_by_page(call_graph)
      |> Compiler.put_impl_mfas(call_graph)

    impl_checking_pages =
      Compiler.pages_checking_permissions_in_impls(listed_reach, unsplit_call_graph)

    reach_by_page =
      Compiler.build_kept_page_reach(
        listed_reach,
        permission_checking_pages ++ impl_checking_pages,
        module_info_plt,
        ir_plt
      )

    {reach_by_page, module_info_plt}
  end
end
