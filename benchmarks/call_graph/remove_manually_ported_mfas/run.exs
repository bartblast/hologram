alias Hologram.Compiler
alias Hologram.Compiler.CallGraph

Benchee.run(
  %{
    "remove_manually_ported_mfas/1" =>
      {fn call_graph ->
         CallGraph.remove_manually_ported_mfas(call_graph)
       end,
       before_scenario: fn _input ->
         module_beam_path_plt = Compiler.build_module_beam_path_plt()
         ir_plt = Compiler.build_ir_plt(module_beam_path_plt)

         Compiler.build_call_graph(ir_plt)
       end,
       before_each: fn call_graph ->
         CallGraph.clone(call_graph)
       end,
       after_each: fn call_graph ->
         CallGraph.stop(call_graph)
       end}
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "remove_manually_ported_mfas/1", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
