alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

# The walk a compile makes per save to find the pages an edit reaches: the modules that changed are
# the targets. A leaf module has few callers, a core one is reached from most pages, and the third
# scenario is the shape of a saved file that defines several modules.
Benchee.run(
  %{
    "1 leaf module" => fn {call_graph, leaf_module, _core_module} ->
      CallGraph.list_modules_reaching(call_graph, [leaf_module])
    end,
    "1 core module" => fn {call_graph, _leaf_module, core_module} ->
      CallGraph.list_modules_reaching(call_graph, [core_module])
    end,
    "10 modules" => fn {call_graph, _leaf_module, _core_module} ->
      CallGraph.list_modules_reaching(call_graph, Enum.take(Reflection.list_pages(), 10))
    end
  },
  before_scenario: fn _input ->
    call_graph = Compiler.build_call_graph()
    leaf_module = hd(Reflection.list_pages())

    {call_graph, leaf_module, Hologram.Component}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.CallGraph.list_modules_reaching/2",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
