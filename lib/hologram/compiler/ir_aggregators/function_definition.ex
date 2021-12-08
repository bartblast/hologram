alias Hologram.Compiler.IR.FunctionDefinition
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: FunctionDefinition do
  def aggregate(%{body: body}) do
    IRAggregator.aggregate(body)
  end
end
