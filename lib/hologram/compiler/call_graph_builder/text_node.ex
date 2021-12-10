# TODO: test

alias Hologram.Compiler.CallGraphBuilder
alias Hologram.Template.VDOM.TextNode

defimpl CallGraphBuilder, for: TextNode do
  def build(_, _, _, _), do: nil
end
