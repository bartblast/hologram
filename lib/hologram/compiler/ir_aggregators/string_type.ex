# TODO: test

alias Hologram.Compiler.IR.StringType
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: StringType do
  def aggregate(_), do: nil
end
