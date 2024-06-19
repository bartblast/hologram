alias Hologram.Commons.FileUtils
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

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
             "maybe_load_call_graph_no_load_1"
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
             "maybe_load_call_graph_do_load_1"
           ])

         call_graph = Compiler.build_call_graph()
         call_graph_dump_path = Path.join(build_dir, Reflection.call_graph_dump_file_name())
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
     description: "Hologram.Compiler.maybe_load_call_graph/1",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
