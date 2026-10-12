alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

# What the compile task pays to list what every page's client code reaches, the MFAs and the
# struct types, which is what the data layer is derived from: one task per page through a shared
# graph, with the server callback analyses computed for the call.
#
# A compile that derives the data layer lists it twice: on the runtime's copy of the graph, which
# is the one measured here, and on the unsplit graph, for the question of which pages check
# permissions.
#
# The fixtures give it 110 pages, 10 of which reach the two components with a parameterized
# query.
Benchee.run(
  %{
    "list_reach_by_page/2" => fn {page_modules, call_graph} ->
      Compiler.list_reach_by_page(page_modules, call_graph)
    end
  },
  before_scenario: fn _input ->
    ir_plt = Compiler.build_ir_plt()
    call_graph = Compiler.build_call_graph(ir_plt)

    # The runtime's copy of the graph: the manually ported MFAs out, which is what the bundles
    # are derived from, and the runtime's MFAs still in, so that a component reached through a
    # runtime MFA is still one the page can reach.
    CallGraph.remove_manually_ported_mfas(call_graph)

    {Reflection.list_pages(), call_graph}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.list_reach_by_page/2", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
