alias Hologram.Benchmarks.Fixtures.Components.DefaultLayout
alias Hologram.Benchmarks.Fixtures.Page1
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "1 templatable" => fn {graph, _templatables, module_info_plt} ->
      CallGraph.server_protocol_dispatch_types(graph, [Page1], module_info_plt)
    end,
    "all templatables" => fn {graph, templatables, module_info_plt} ->
      CallGraph.server_protocol_dispatch_types(graph, templatables, module_info_plt)
    end
  },
  before_scenario: fn _input ->
    call_graph = Compiler.build_call_graph()
    graph = CallGraph.get_graph(call_graph)
    templatables = [DefaultLayout | Reflection.list_pages()]

    {graph, templatables, CallGraph.module_info_plt(call_graph)}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.CallGraph.server_protocol_dispatch_types/3",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
