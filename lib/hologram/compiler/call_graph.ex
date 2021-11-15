defprotocol Hologram.Compiler.CallGraph do
  def build(ir, call_graph, module_defs, from_vertex \\ nil)
end
