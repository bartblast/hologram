# TODO: test

alias Hologram.Compiler.ModuleDefAggregator
alias Hologram.Template.VDOM.TextNode

defimpl ModuleDefAggregator, for: TextNode do
  def aggregate(_), do: nil
end
