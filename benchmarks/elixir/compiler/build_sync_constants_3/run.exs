alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

# What the compile task pays to derive what the client's data layer is compiled with, once per
# compile that derives the data layer: the modules every page reaches, the entity types among
# them, the queries of every reached component and the entity types those name, and the argument
# names of the parameterized captures.
#
# The function sweeps the entity types itself, once per call, so the number holds one
# Hologram.Reflection.list_entities/0, which has a benchmark of its own.
#
# The fixtures give it 110 pages, 10 of which reach the two components with a parameterized
# query. The result names 11 of the 21 entity types, the ones the argument-entity query fits, and
# the prop params of both components. No page checks permissions, so neither the grant type nor
# the policied types join.
Benchee.run(
  %{
    "build_sync_constants/3" => fn {reach_by_page, module_info_plt, permission_checking?} ->
      Compiler.build_sync_constants(reach_by_page, module_info_plt, permission_checking?)
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
    reach_by_page = Compiler.list_reach_by_page(page_modules, call_graph)

    {reach_by_page, module_info_plt, permission_checking_pages != []}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_sync_constants/3",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
