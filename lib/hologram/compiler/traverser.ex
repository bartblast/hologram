defprotocol Hologram.Compiler.Traverser do
  @fallback_to_any true
  
  def traverse(ir, acc, from_vertex \\ nil)
end
