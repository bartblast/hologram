alias Hologram.Compiler.CallGraphBuilder

defimpl CallGraphBuilder, for: List do
  def build(list, module_defs, templates, from_vertex) do
    Enum.each(list, &CallGraphBuilder.build(&1, module_defs, templates, from_vertex))
  end
end
