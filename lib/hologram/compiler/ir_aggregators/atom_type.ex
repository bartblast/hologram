# TODO: test

alias Hologram.Compiler.IR.AtomType
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: AtomType do
  def aggregate(_), do: nil
end
