# TODO: test

alias Hologram.Compiler.CallGraphBuilder

defimpl CallGraphBuilder, for: Atom do
  def build(_, _, _), do: nil
end
