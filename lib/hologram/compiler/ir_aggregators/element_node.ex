alias Hologram.Compiler.IRAggregator
alias Hologram.Template.VDOM.ElementNode

defimpl IRAggregator, for: ElementNode do
  def aggregate(%{attrs: attrs, children: children}) do
    IRAggregator.aggregate(attrs)
    IRAggregator.aggregate(children)
  end
end
