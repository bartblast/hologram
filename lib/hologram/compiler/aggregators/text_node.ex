alias Hologram.Compiler.Aggregator
alias Hologram.Template.VDOM.TextNode

defimpl Aggregator, for: TextNode do
  def aggregate(_, module_defs), do: module_defs
end
