defmodule Hologram.Compiler.Normalizer do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.Reflection

  @doc """
  Normalizes Elixir AST.

  ## Examples

      iex> ast = Hologram.Compiler.Parser.parse!("if true, do: 987")
      {:if, [line: 1], [true, [do: 987]]}
      iex> Normalizer.normalize(ast)
      {:if, [line: 1], [true, [do: {:__block__, [], [987]}, else: {:__block__, [], [nil]}]]}
  """
  def normalize(ast)

  def normalize({:case, line, [condition, [do: clauses]]}) do
    {:case, line, [condition, [do: normalize(clauses)]]}
  end

  def normalize({:->, line, [pattern, {:__block__, [], exprs}]}) do
    {:->, line, [pattern, {:__block__, [], normalize(exprs)}]}
  end

  def normalize({:->, line, [pattern, expr]}) do
    {:->, line, [pattern, {:__block__, [], [normalize(expr)]}]}
  end

  def normalize({:if, line, [condition, [do: do_exprs]]}) do
    normalize({:if, line, [condition, [do: do_exprs, else: nil]]})
  end

  def normalize({:if, line, [condition, [do: do_exprs, else: else_exprs]]}) do
    {:if, line, [condition, normalize(do: do_exprs) ++ normalize(else: else_exprs)]}
  end

  def normalize(do: {:__block__, [], exprs}) do
    [do: {:__block__, [], Enum.map(exprs, &normalize/1)}]
  end

  def normalize(do: expr) do
    [do: {:__block__, [], [normalize(expr)]}]
  end

  def normalize(else: {:__block__, [], exprs}) do
    [else: {:__block__, [], Enum.map(exprs, &normalize/1)}]
  end

  def normalize(else: expr) do
    [else: {:__block__, [], [normalize(expr)]}]
  end

  def normalize(ast) when is_atom(ast) do
    if Reflection.is_alias?(ast) do
      segments = Helpers.alias_segments(ast)
      {:__aliases__, [alias: false], segments}
    else
      ast
    end
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
