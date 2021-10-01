alias Hologram.Compiler.IR.FunctionCall
alias Hologram.Template.Evaluator

defimpl Evaluator, for: FunctionCall do
  def evaluate(%{module: module, function: function, params: params}, state) do
    params = Enum.map(params, &Evaluator.evaluate(&1, state))
    apply(module, function, params)
  end
end
