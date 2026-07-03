alias Hologram.Benchmarks.Fixtures.Components.DefaultLayout
alias Hologram.Benchmarks.Fixtures.Page1
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "1 templatable" => fn {graph, _templatables} ->
      CallGraph.server_protocol_dispatch_types(graph, [Page1])
    end,
    "all templatables" => fn {graph, templatables} ->
      CallGraph.server_protocol_dispatch_types(graph, templatables)
    end
  },
  before_scenario: fn _input ->
    call_graph = Compiler.build_call_graph()
    graph = CallGraph.get_graph(call_graph)
    templatables = [DefaultLayout | Reflection.list_pages()]

    {graph, templatables}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.CallGraph.server_protocol_dispatch_types/2",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
