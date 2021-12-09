defprotocol Hologram.Compiler.CallGraphBuilder do
  def build(ir, module_defs, from_vertex \\ nil)
end
