alias Hologram.Compiler.IRAggregator
alias Hologram.Template.VDOM.Component

defimpl IRAggregator, for: Component do
  def aggregate(%{module: module, props: props, children: children}) do
    IRAggregator.aggregate(children)
    IRAggregator.aggregate(module)
    IRAggregator.aggregate(props)
  end
end
