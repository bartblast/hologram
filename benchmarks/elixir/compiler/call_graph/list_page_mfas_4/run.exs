alias Hologram.Benchmarks.Fixtures.Page1
alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "list_page_mfas/4" => fn {graph, analyses, module_info_plt} ->
      CallGraph.list_page_mfas(graph, Page1, analyses, module_info_plt)
    end
  },
  before_scenario: fn _input ->
    call_graph = Compiler.build_call_graph()
    graph = CallGraph.get_graph(call_graph)
    module_info_plt = CallGraph.module_info_plt(call_graph)
    templatables = Reflection.list_pages() ++ Reflection.list_components()

    # Every analysis is in the PLT up front, so that the walk is what is measured.
    analyses_items =
      graph
      |> CallGraph.server_callback_analysis_by_templatable(templatables, module_info_plt)
      |> Map.to_list()

    {graph, PLT.start(items: analyses_items), module_info_plt}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.CallGraph.list_page_mfas/4",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
