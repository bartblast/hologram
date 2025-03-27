alias Hologram.Compiler
alias Hologram.Compiler.CallGraph

Benchee.run(
  %{
    "build_call_graph/1" => fn ir_plt ->
      Compiler.build_call_graph(ir_plt)
    end
  },
  before_scenario: fn _input ->
    Compiler.build_ir_plt()
  end,
  after_each: fn call_graph ->
    CallGraph.stop(call_graph)
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_call_graph/1", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
