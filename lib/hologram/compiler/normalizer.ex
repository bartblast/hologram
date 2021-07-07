defmodule Hologram.Compiler.Normalizer do
  def normalize({elem_1, elem_2, elem_3}) do
    {
      normalize(elem_1),
      normalize(elem_2),
      normalize(elem_3)
    }
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

  def normalize(ast), do: ast
end
