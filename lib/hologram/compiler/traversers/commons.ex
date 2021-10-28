alias Hologram.Compiler.Reflection

defmodule Hologram.Compiler.Traverser.Commons do
  def has_edge?(graph, from_vertex, to_vertex) do
    edges = Graph.edges(graph, from_vertex, to_vertex)
    Enum.count(edges) == 1
  end

  def maybe_add_module_def(map, module) do
    unless map[module] || Reflection.standard_lib?(module) do
      module_def = Reflection.module_definition(module)
      Map.put(map, module, module_def)
    else
      map
    end
  end
end
