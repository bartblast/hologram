defprotocol Hologram.Compiler.Traverser do
  def traverse(ir, acc, from_vertex \\ nil)
end
