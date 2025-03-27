alias Hologram.Benchmarks.Fixtures.Page1
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "build_page_js/4" => fn {call_graph, ir_plt, js_dir} ->
      Compiler.build_page_js(Page1, call_graph, ir_plt, js_dir)
    end
  },
  before_scenario: fn _input ->
    ir_plt = Compiler.build_ir_plt()
    call_graph = Compiler.build_call_graph(ir_plt)
    runtime_mfas = CallGraph.list_runtime_mfas(call_graph)
    call_graph_for_pages = CallGraph.remove_runtime_mfas!(call_graph, runtime_mfas)
    js_dir = Path.join([Reflection.root_dir(), "assets", "js"])

    {call_graph_for_pages, ir_plt, js_dir}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_page_js/4", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
