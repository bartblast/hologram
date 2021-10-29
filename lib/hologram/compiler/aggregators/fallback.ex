alias Hologram.Compiler.Aggregator

defimpl Aggregator, for: Any do
  def aggregate(_, module_defs), do: module_defs
end
