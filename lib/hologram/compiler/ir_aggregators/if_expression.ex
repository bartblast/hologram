alias Hologram.Compiler.IR.IfExpression
alias Hologram.Compiler.IRAggregator

defimpl IRAggregator, for: IfExpression do
  def aggregate(%{condition: condition, do: do_clause, else: else_clause}) do
    IRAggregator.aggregate(condition)
    IRAggregator.aggregate(do_clause)
    IRAggregator.aggregate(else_clause)
  end
end
