alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

# What the compile task pays to fold each page's reach into what the data layer keeps of it: the
# modules the page reaches, the components among them and whether it checks permissions. A cold
# compile pays it for every page. A compile that derives the data layer pays it only for the pages
# whose reach the edit can have moved, which it walks again (see the list_reach_by_page_2
# benchmark for the walk).
#
# The fixtures give it 110 pages.
Benchee.run(
  %{
    "build_kept_page_reach/3" => fn {listed_reach, permission_checking_pages, module_info_plt} ->
      Compiler.build_kept_page_reach(listed_reach, permission_checking_pages, module_info_plt)
    end
  },
  before_scenario: fn _input ->
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

    CallGraph.remove_manually_ported_mfas(call_graph)

    # Listed with the runtime's MFAs still in the graph, as the compile task lists it: a
    # component reached through a runtime MFA is still one the page can reach.
    listed_reach = Compiler.list_reach_by_page(page_modules, call_graph)

    {listed_reach, permission_checking_pages, module_info_plt}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_kept_page_reach/3",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
