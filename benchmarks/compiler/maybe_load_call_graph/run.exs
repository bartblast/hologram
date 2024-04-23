alias Hologram.Commons.FileUtils
alias Hologram.Commons.Reflection
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph

Benchee.run(
  %{
    "no load" =>
      {fn build_dir ->
         Compiler.maybe_load_call_graph(build_dir)
       end,
       before_scenario: fn _input ->
         build_dir =
           Path.join([
             Reflection.tmp_dir(),
             "benchmarks",
             "compiler",
             "maybe_load_call_graph_no_load"
           ])

         FileUtils.recreate_dir(build_dir)

         build_dir
       end},
    "do load" =>
      {fn build_dir ->
         Compiler.maybe_load_call_graph(build_dir)
       end,
       before_scenario: fn _input ->
         build_dir =
           Path.join([
             Reflection.tmp_dir(),
             "benchmarks",
             "compiler",
             "maybe_load_call_graph_do_load"
           ])

         module_beam_path_plt = Compiler.build_module_beam_path_plt()
         ir_plt = Compiler.build_ir_plt(module_beam_path_plt)
         call_graph = CallGraph.build_from_ir_plt(ir_plt)

         call_graph_dump_path = Path.join(build_dir, "call_graph.bin")
         CallGraph.dump(call_graph, call_graph_dump_path)

         build_dir
       end}
  },
  after_each: fn {call_graph, _call_graph_dump_path} ->
    CallGraph.stop(call_graph)
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "maybe_load_call_graph/1", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
