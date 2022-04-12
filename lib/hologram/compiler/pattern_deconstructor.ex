defprotocol Hologram.Compiler.PatternDeconstructor do
  @fallback_to_any true
  
  def deconstruct(pattern, path \\ [])
end
