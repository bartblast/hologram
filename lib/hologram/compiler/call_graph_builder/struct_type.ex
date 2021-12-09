# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.StructType

defimpl CallGraphBuilder, for: StructType do
  def build(%{data: data}, module_defs, from_vertex) do
    CallGraphBuilder.build(data, module_defs, from_vertex)
  end
end
