# TODO: test

alias Hologram.Compiler.CallGraphBuilder

defimpl CallGraphBuilder, for: Map do
  def build(map, module_defs, from_vertex) do
    map
    |> Map.to_list()
    |> CallGraphBuilder.build(module_defs, from_vertex)
  end
end
