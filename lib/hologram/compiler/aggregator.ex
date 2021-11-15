defprotocol Hologram.Compiler.Aggregator do
  def aggregate(ir, module_defs \\ %{})
end
