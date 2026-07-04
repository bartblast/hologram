alias Hologram.Benchmarks.Fixtures.Page1
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "build_page_js/6" => fn {call_graph, ir_plt, async_mfas,
                             server_callback_analysis_by_templatable, js_dir} ->
      Compiler.build_page_js(
        Page1,
        call_graph,
        ir_plt,
        async_mfas,
        server_callback_analysis_by_templatable,
        js_dir
      )
    end
  },
  before_scenario: fn _input ->
    ir_plt = Compiler.build_ir_plt()
    call_graph = Compiler.build_call_graph(ir_plt)
    async_mfas = CallGraph.list_async_mfas(call_graph)
    runtime_mfas = CallGraph.list_runtime_mfas(call_graph)
    call_graph_for_pages = CallGraph.remove_runtime_mfas!(call_graph, runtime_mfas)

    graph = CallGraph.get_graph(call_graph_for_pages)
    templatables = Reflection.list_pages() ++ Reflection.list_components()

    server_callback_analysis_by_templatable =
      CallGraph.server_callback_analysis_by_templatable(graph, templatables)

    js_dir = Path.join([Reflection.root_dir(), "assets", "js"])

    {call_graph_for_pages, ir_plt, async_mfas, server_callback_analysis_by_templatable, js_dir}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_page_js/6", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
