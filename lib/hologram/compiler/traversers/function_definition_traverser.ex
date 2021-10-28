alias Hologram.Compiler.IR.FunctionDefinition
alias Hologram.Compiler.Traverser

defimpl Traverser, for: FunctionDefinition do
  def traverse(%{module: module, name: name, body: body}, {map, graph}, _) do
    from_vertex = {module, name}
    Enum.reduce(body, {map, graph}, &Traverser.traverse(&1, &2, from_vertex))
  end
end
