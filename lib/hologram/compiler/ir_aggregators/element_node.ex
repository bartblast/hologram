alias Hologram.Template.VDOM.ElementNode
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: ElementNode do
  def aggregate(%{attrs: attrs, children: children}) do
    IRAggregator.aggregate(attrs)
    IRAggregator.aggregate(children)
  end
end
