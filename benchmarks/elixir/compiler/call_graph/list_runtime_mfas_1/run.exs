alias Hologram.Compiler
alias Hologram.Compiler.CallGraph

Benchee.run(
  %{
    "list_runtime_mfas/1" => fn call_graph ->
      CallGraph.list_runtime_mfas(call_graph)
    end
  },
  before_scenario: fn _input ->
    Compiler.build_call_graph()
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.CallGraph.list_runtime_mfas/1",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
