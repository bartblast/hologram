defmodule Hologram.Compiler.CaseExpressionTransformer do
  alias Hologram.Compiler.{Context, Helpers, Transformer}
  alias Hologram.Compiler.IR.CaseExpression

  def transform({:case, _, [condition, [do: clauses]]}, %Context{} = context) do
    %CaseExpression{
      condition: Transformer.transform(condition, context),
      clauses: Enum.map(clauses, &build_clause(&1, context))
    }
  end

  defp build_clause({:->, _, [[pattern], {:__block__, [], body}]}, context) do
    pattern = Transformer.transform(pattern, context)
    bindings = Helpers.aggregate_bindings_from_expression(pattern)
    body = Enum.map(body, &Transformer.transform(&1, context))

    %{
      pattern: pattern,
      bindings: bindings,
      body: body
    }
  end
end
