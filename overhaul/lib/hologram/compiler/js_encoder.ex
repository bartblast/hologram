defprotocol Hologram.Compiler.JSEncoder do
  def encode(ir, context, opts)
end
