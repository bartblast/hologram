defmodule Hologram.Compiler.Normalizer do
  def normalize({:case, line, [condition, [do: clauses]]}) do
    {:case, line, [condition, [do: normalize(clauses)]]}
  end

  def normalize({:->, line, [pattern, {:__block__, [], exprs}]}) do
    {:->, line, [pattern, {:__block__, [], normalize(exprs)}]}
  end

  def normalize({:->, line, [pattern, expr]}) do
    {:->, line, [pattern, {:__block__, [], [normalize(expr)]}]}
  end

  def normalize(do: {:__block__, [], exprs}) do
    [do: {:__block__, [], Enum.map(exprs, &normalize/1)}]
  end

  def normalize(do: expr) do
    [do: {:__block__, [], [normalize(expr)]}]
  end

  def normalize(ast) when is_list(ast) do
    Enum.map(ast, &normalize/1)
  end

  def normalize({elem_1, elem_2, elem_3}) do
    {
      normalize(elem_1),
      normalize(elem_2),
      normalize(elem_3)
    }
  end

  def normalize(ast), do: ast
end
