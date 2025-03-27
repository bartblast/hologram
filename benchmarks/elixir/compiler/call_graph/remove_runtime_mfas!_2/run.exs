alias Hologram.Compiler
alias Hologram.Compiler.CallGraph

Benchee.run(
  %{
    "remove_runtime_mfas!/2" =>
      {fn {call_graph, runtime_mfas} ->
         CallGraph.remove_runtime_mfas!(call_graph, runtime_mfas)
       end,
       before_scenario: fn _input ->
         call_graph = Compiler.build_call_graph()
         runtime_mfas = CallGraph.list_runtime_mfas(call_graph)

         {call_graph, runtime_mfas}
       end,
       before_each: fn {call_graph, runtime_mfas} ->
         {CallGraph.clone(call_graph), runtime_mfas}
       end,
       after_each: fn call_graph ->
         CallGraph.stop(call_graph)
       end}
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.CallGraph.remove_runtime_mfas!/2",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
