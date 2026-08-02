alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "server_callback_analysis_by_templatable/2" => fn {graph, templatables} ->
      CallGraph.server_callback_analysis_by_templatable(graph, templatables)
    end
  },
  before_scenario: fn _input ->
    pages = Reflection.list_pages()

    call_graph = Compiler.build_call_graph()
    runtime_mfas = CallGraph.list_runtime_mfas(call_graph, pages)
    call_graph_for_pages = CallGraph.remove_runtime_mfas!(call_graph, runtime_mfas)

    graph = CallGraph.get_graph(call_graph_for_pages)
    templatables = pages ++ Reflection.list_components()

    {graph, templatables}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.CallGraph.server_callback_analysis_by_templatable/2",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
