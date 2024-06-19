alias Hologram.Commons.FileUtils
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "dump dir exists, dump file exists" =>
      {fn {call_graph, dump_path} ->
         CallGraph.dump(call_graph, dump_path)
       end,
       before_scenario: fn {call_graph, _dump_dir, dump_path} ->
         CallGraph.dump(call_graph, dump_path)
         {call_graph, dump_path}
       end},
    "dump dir exists, dump file doesn't exist" =>
      {fn {call_graph, dump_path} ->
         CallGraph.dump(call_graph, dump_path)
       end,
       before_scenario: fn {call_graph, dump_dir, dump_path} ->
         FileUtils.recreate_dir(dump_dir)
         {call_graph, dump_path}
       end,
       before_each: fn {call_graph, dump_path} ->
         File.rm(dump_path)
         {call_graph, dump_path}
       end},
    "dump dir doesn't exists" =>
      {fn {call_graph, dump_path} ->
         CallGraph.dump(call_graph, dump_path)
       end,
       before_each: fn {call_graph, dump_dir, dump_path} ->
         File.rmdir(dump_dir)
         {call_graph, dump_path}
       end}
  },
  before_scenario: fn _input ->
    call_graph = Compiler.build_call_graph()

    dump_dir = Path.join([Reflection.tmp_dir(), "benchmarks", "compiler", "call_graph", "dump_2"])
    dump_path = Path.join(dump_dir, Reflection.call_graph_dump_file_name())

    {call_graph, dump_dir, dump_path}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.CallGraph.dump/2", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
