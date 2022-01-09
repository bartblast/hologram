# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Compiler.IR.AccessOperator

defimpl CallGraphBuilder, for: AccessOperator do
  def build(%{data: data, key: key}, module_defs, templates, from_vertex) do
    CallGraphBuilder.build(data, module_defs, templates, from_vertex)
    CallGraphBuilder.build(key, module_defs, templates, from_vertex)
  end
end
