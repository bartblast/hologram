alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

# What the compile task pays to validate the slot bindings of every component the pages reach,
# once per compile that derives the data layer: each page's reach narrowed to its components,
# then each distinct component validated once -
# Hologram.Compiler.QueryExtractor.validate_slot_bindings!/1 has a benchmark of its own.
#
# The fixtures give it 110 pages, 10 of which reach the two components with a parameterized
# query. The other components the pages reach declare no query prop and take the fast path.
Benchee.run(
  %{
    "validate_slot_bindings!/2" => fn {reach_by_page, module_info_plt} ->
      Compiler.validate_slot_bindings!(reach_by_page, module_info_plt)
    end
  },
  before_scenario: fn _input ->
    ir_plt = Compiler.build_ir_plt()
    call_graph = Compiler.build_call_graph(ir_plt)
    module_info_plt = CallGraph.module_info_plt(call_graph)

    # The runtime's copy of the graph: the manually ported MFAs out, which is what the bundles
    # are derived from, and the runtime's MFAs still in, so that a component reached through a
    # runtime MFA is still one the page can reach.
    CallGraph.remove_manually_ported_mfas(call_graph)

    reach_by_page = Compiler.list_reach_by_page(Reflection.list_pages(), call_graph)

    {reach_by_page, module_info_plt}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.validate_slot_bindings!/2",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
