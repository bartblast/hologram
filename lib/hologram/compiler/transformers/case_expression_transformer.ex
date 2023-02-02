defmodule Hologram.Compiler.CaseExpressionTransformer do
  alias Hologram.Compiler.{Helpers, Transformer}
  alias Hologram.Compiler.IR.{CaseConditionAccess, CaseExpression}

  def transform({:case, _, [condition, [do: clauses]]}) do
    %CaseExpression{
      condition: Transformer.transform(condition),
      clauses: Enum.map(clauses, &build_clause/1)
    }
  end

  defp build_clause({:->, _, [[pattern], body]}) do
    pattern = Transformer.transform(pattern)
    body = Transformer.transform(body)

    bindings =
      Helpers.aggregate_bindings_from_expression(pattern)
      |> Enum.map(&prepend_symbol_access/1)

    %{
      pattern: pattern,
      bindings: bindings,
      body: body
    }
  end

  defp prepend_symbol_access(binding) do
    %{binding | access_path: [%CaseConditionAccess{} | binding.access_path]}
  end
end
