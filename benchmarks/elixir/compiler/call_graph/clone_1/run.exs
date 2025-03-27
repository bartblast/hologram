alias Hologram.Compiler
alias Hologram.Compiler.CallGraph

Benchee.run(
  %{
    "clone/1" =>
      {fn call_graph ->
         CallGraph.clone(call_graph)
       end,
       after_each: fn call_graph ->
         CallGraph.stop(call_graph)
       end}
  },
  before_scenario: fn _input ->
    Compiler.build_call_graph()
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.CallGraph.clone/1", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
