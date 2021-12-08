# TODO: test

alias Hologram.Compiler.IRAggregator
alias Hologram.Template.VDOM.TextNode

defimpl IRAggregator, for: TextNode do
  def aggregate(_), do: nil
end
