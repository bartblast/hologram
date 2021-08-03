defprotocol Hologram.Compiler.Encoder do
  def encode(ir, context, opts)
end
