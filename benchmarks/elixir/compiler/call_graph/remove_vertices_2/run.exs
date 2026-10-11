alias Hologram.Compiler
alias Hologram.Compiler.CallGraph

# The removal is queued in the graph's process and the call returns at once, so the measured
# function also reads from the graph: the process answers the read after the removal, which makes
# the function take as long as the work.
#
# The read matters for a second reason. Benchee repeats a function too fast for the clock to time
# in one call (10 μs on macOS), and then runs the hooks inside the sample. Timed without the
# read, the call is a message send of a microsecond or two, and a sample is a clone and a stop.
await_graph = fn call_graph ->
  CallGraph.has_vertex?(call_graph, Kernel)
  call_graph
end

Benchee.run(
  %{
    "1 vertex" =>
      {fn {call_graph, vertices} ->
         CallGraph.remove_vertices(call_graph, Enum.take(vertices, 1))
         await_graph.(call_graph)
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
         await_graph.(call_graph)
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
         await_graph.(call_graph)
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
         await_graph.(call_graph)
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
         await_graph.(call_graph)
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
         await_graph.(call_graph)
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
  time: 10
)
