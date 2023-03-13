alias Hologram.Compiler.ModuleDefAggregator
alias Hologram.Template.VDOM.ElementNode

defimpl ModuleDefAggregator, for: ElementNode do
  def aggregate(%{attrs: attrs, children: children}) do
    ModuleDefAggregator.aggregate(attrs)
    ModuleDefAggregator.aggregate(children)
  end
end
