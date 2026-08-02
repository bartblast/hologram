alias Hologram.Benchmarks.Fixtures.Page1
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "list_page_mfas/3" => fn {call_graph, server_callback_analysis_by_templatable} ->
      CallGraph.list_page_mfas(call_graph, Page1, server_callback_analysis_by_templatable)
    end
  },
  before_scenario: fn _input ->
    call_graph = Compiler.build_call_graph()
    graph = CallGraph.get_graph(call_graph)
    templatables = Reflection.list_pages() ++ Reflection.list_components()

    server_callback_analysis_by_templatable =
      CallGraph.server_callback_analysis_by_templatable(graph, templatables)

    {call_graph, server_callback_analysis_by_templatable}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.CallGraph.list_page_mfas/3",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
