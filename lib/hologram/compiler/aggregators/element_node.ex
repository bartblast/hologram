alias Hologram.Compiler.Aggregator
alias Hologram.Template.VDOM.ElementNode

defimpl Aggregator, for: ElementNode do
  def aggregate(%{attrs: attrs, children: children}, module_defs) do
    module_defs = Aggregator.aggregate(attrs, module_defs)
    Aggregator.aggregate(children, module_defs)
  end
end
