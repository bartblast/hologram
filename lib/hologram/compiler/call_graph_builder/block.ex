alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.Block

defimpl CallGraphBuilder, for: Block do
  def build(%{expressions: expressions}, module_defs, templates, from_vertex) do
    Enum.each(expressions, &CallGraphBuilder.build(&1, module_defs, templates, from_vertex))
  end
end
