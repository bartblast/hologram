defprotocol Hologram.Compiler.CallGraphBuilder do
  def build(ir, module_defs, templates, from_vertex)
end
