defprotocol Hologram.Compiler.Aggregator do
  @fallback_to_any true
  
  def aggregate(ir, module_defs)
end
