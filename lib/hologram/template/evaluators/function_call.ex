alias Hologram.Compiler.IR.FunctionCall
alias Hologram.Template.Evaluator

defimpl Evaluator, for: FunctionCall do
  def evaluate(%{module: module, function: function, args: args}, state) do
    args = Enum.map(args, &Evaluator.evaluate(&1, state))
    apply(module, function, args)
  end
end
