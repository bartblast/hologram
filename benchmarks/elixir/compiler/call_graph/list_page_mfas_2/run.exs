alias Hologram.Benchmarks.Fixtures.Page1
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph

Benchee.run(
  %{
    "list_page_mfas/2" => fn call_graph ->
      CallGraph.list_page_mfas(call_graph, Page1)
    end
  },
  before_scenario: fn _input ->
    Compiler.build_call_graph()
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.CallGraph.list_page_mfas/2",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
