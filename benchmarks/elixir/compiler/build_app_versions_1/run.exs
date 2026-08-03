alias Hologram.Compiler
alias Hologram.Compiler.CallGraph

Benchee.run(
  %{
    "build_app_versions/1" => fn call_graph ->
      Compiler.build_app_versions(call_graph)
    end
  },
  before_scenario: fn _input ->
    Compiler.build_call_graph(Compiler.build_ir_plt())
  end,
  after_scenario: fn call_graph ->
    CallGraph.stop(call_graph)
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_app_versions/1", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
