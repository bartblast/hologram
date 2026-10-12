alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

# What the compile task pays to render the statement the runtime script sets the client's data
# layer constants with, once per compile that derives the data layer: the model of the entity
# types the client holds, the prop params and the model hash.
#
# The function sweeps the entity types itself, once per call, to tell whether the project has a
# data model at all, so the number holds one Hologram.Reflection.list_entities/0, which has a
# benchmark of its own. The model hash is cached for the lifetime of the runtime, so every sample
# after the first reads it rather than derives it.
#
# The fixtures give it a model of 11 entity types, the ones the 10 pages with a query reach, and
# the prop params of two components. The statement is 4,593 bytes.
Benchee.run(
  %{
    "build_sync_constants_js/1" => fn sync_constants ->
      Compiler.build_sync_constants_js(sync_constants)
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
      |> Compiler.pages_checking_permissions(module_info_plt)

    CallGraph.remove_manually_ported_mfas(call_graph)

    # Listed with the runtime's MFAs still in the graph, as the compile task lists it: a
    # component reached through a runtime MFA is still one the page can reach.
    page_modules
    |> Compiler.list_reach_by_page(call_graph)
    |> Compiler.build_sync_constants(module_info_plt, permission_checking_pages != [])
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_sync_constants_js/1",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
