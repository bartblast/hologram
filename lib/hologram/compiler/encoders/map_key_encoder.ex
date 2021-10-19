defprotocol Hologram.Compiler.MapKeyEncoder do
  def encode(ir, context, opts)
end
