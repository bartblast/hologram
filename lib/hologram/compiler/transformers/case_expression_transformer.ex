defmodule Hologram.Compiler.CaseExpressionTransformer do
  alias Hologram.Compiler.{Context, Helpers, Transformer}
  alias Hologram.Compiler.IR.{CaseConditionAccess, CaseExpression}

  def transform({:case, _, [condition, [do: clauses]]}, %Context{} = context) do
    %CaseExpression{
      condition: Transformer.transform(condition, context),
      clauses: Enum.map(clauses, &build_clause(&1, context))
    }
  end

  defp build_clause({:->, _, [[pattern], {:__block__, [], body}]}, context) do
    pattern = Transformer.transform(pattern, context)
    body = Enum.map(body, &Transformer.transform(&1, context))

    bindings =
      Helpers.aggregate_bindings_from_expression(pattern)
      |> Enum.map(&prepend_variable_access/1)

    %{
      pattern: pattern,
      bindings: bindings,
      body: body
    }
  end

  defp prepend_variable_access(binding) do
    %{binding | access_path: [%CaseConditionAccess{} | binding.access_path]}
  end
end
