defprotocol Hologram.Compiler.Traverser2 do
  @fallback_to_any true

  def traverse(ir, acc, callback)
end
