alias Hologram.Compiler.{CallGraph, CallGraphBuilder, Reflection}
alias Hologram.Compiler.IR.FunctionCall

defimpl CallGraphBuilder, for: FunctionCall do
  def build(%{module: module, function: function, args: args}, module_defs, from_vertex) do
    CallGraphBuilder.build(args, module_defs, from_vertex)

    unless Reflection.standard_lib?(module) do
      CallGraphBuilder.build(module_defs[module], module_defs)
      CallGraph.add_edge(from_vertex, {module, function})
    end
  end
end
