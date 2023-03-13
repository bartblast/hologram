# TODO: test

alias Hologram.Compiler.CallGraphBuilder

defimpl CallGraphBuilder, for: Map do
  def build(map, module_defs, templates, from_vertex) do
    map
    |> Map.to_list()
    |> CallGraphBuilder.build(module_defs, templates, from_vertex)
  end
end
