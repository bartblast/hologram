alias Hologram.Compiler.ModuleDefAggregator
alias Hologram.Template.VDOM.Component

defimpl ModuleDefAggregator, for: Component do
  def aggregate(%{module: module, props: props, children: children}) do
    ModuleDefAggregator.aggregate(children)
    ModuleDefAggregator.aggregate(module)
    ModuleDefAggregator.aggregate(props)
  end
end
