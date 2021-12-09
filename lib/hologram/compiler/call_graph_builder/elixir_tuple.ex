# TODO: test

alias Hologram.Compiler.CallGraphBuilder

defimpl CallGraphBuilder, for: Tuple do
  def build(tuple, module_defs, from_vertex) do
    tuple
    |> Tuple.to_list()
    |> CallGraphBuilder.build(module_defs, from_vertex)
  end
end
