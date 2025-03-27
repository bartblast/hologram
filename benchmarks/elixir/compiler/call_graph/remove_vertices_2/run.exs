alias Hologram.Compiler
alias Hologram.Compiler.CallGraph

Benchee.run(
  %{
    "1 vertex" =>
      {fn {call_graph, vertices} ->
         CallGraph.remove_vertices(call_graph, Enum.take(vertices, 1))
       end,
       before_each: fn {call_graph, vertices} ->
         {CallGraph.clone(call_graph), vertices}
       end,
       after_each: fn call_graph ->
         CallGraph.stop(call_graph)
       end},
    "2 vertices" =>
      {fn {call_graph, vertices} ->
         CallGraph.remove_vertices(call_graph, Enum.take(vertices, 2))
       end,
       before_each: fn {call_graph, vertices} ->
         {CallGraph.clone(call_graph), vertices}
       end,
       after_each: fn call_graph ->
         CallGraph.stop(call_graph)
       end},
    "4 vertices" =>
      {fn {call_graph, vertices} ->
         CallGraph.remove_vertices(call_graph, Enum.take(vertices, 4))
       end,
       before_each: fn {call_graph, vertices} ->
         {CallGraph.clone(call_graph), vertices}
       end,
       after_each: fn call_graph ->
         CallGraph.stop(call_graph)
       end},
    "8 vertices" =>
      {fn {call_graph, vertices} ->
         CallGraph.remove_vertices(call_graph, Enum.take(vertices, 8))
       end,
       before_each: fn {call_graph, vertices} ->
         {CallGraph.clone(call_graph), vertices}
       end,
       after_each: fn call_graph ->
         CallGraph.stop(call_graph)
       end},
    "16 vertices" =>
      {fn {call_graph, vertices} ->
         CallGraph.remove_vertices(call_graph, Enum.take(vertices, 16))
       end,
       before_each: fn {call_graph, vertices} ->
         {CallGraph.clone(call_graph), vertices}
       end,
       after_each: fn call_graph ->
         CallGraph.stop(call_graph)
       end},
    "32 vertices" =>
      {fn {call_graph, vertices} ->
         CallGraph.remove_vertices(call_graph, Enum.take(vertices, 32))
       end,
       before_each: fn {call_graph, vertices} ->
         {CallGraph.clone(call_graph), vertices}
       end,
       after_each: fn call_graph ->
         CallGraph.stop(call_graph)
       end}
  },
  before_scenario: fn _input ->
    call_graph = Compiler.build_call_graph()
    vertices = CallGraph.vertices(call_graph)
    {call_graph, vertices}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.CallGraph.remove_vertices/2",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
