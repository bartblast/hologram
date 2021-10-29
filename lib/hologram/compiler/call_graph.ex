defprotocol Hologram.Compiler.CallGraph do
  @fallback_to_any true

  def build(ir, call_graph, module_defs)
end
