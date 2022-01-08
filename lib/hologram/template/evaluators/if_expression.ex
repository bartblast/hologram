alias Hologram.Compiler.IR.IfExpression
alias Hologram.Template.Evaluator

defimpl Evaluator, for: IfExpression do
  def evaluate(%{ast: ast}, bindings) do
    bindings = Map.to_list(bindings)
    
    Code.eval_quoted(ast, bindings)
    |> elem(0)
  end
end
