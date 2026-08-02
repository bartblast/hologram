alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "list_runtime_mfas/2" => fn {call_graph, pages} ->
      CallGraph.list_runtime_mfas(call_graph, pages)
    end
  },
  before_scenario: fn _input ->
    call_graph = Compiler.build_call_graph()
    pages = Reflection.list_pages()

    {call_graph, pages}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.CallGraph.list_runtime_mfas/2",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
