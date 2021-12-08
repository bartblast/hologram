defprotocol Hologram.Compiler.IRAggregator do
  # TODO: disable fallback
  @fallback_to_any true
  
  def aggregate(ir)
end
