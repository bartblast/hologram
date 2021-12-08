alias Hologram.Compiler.IR.FunctionCall
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: FunctionCall do
  def aggregate(%{module: module, args: args}) do
    IRAggregator.aggregate(module)
    IRAggregator.aggregate(args)
  end
end
