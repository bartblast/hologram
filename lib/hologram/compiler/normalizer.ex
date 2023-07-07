defmodule Hologram.Compiler.Normalizer do
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.Reflection

  @doc """
  Normalizes Elixir AST by ensuring that:
  * single expression blocks are wrapped in __block__ tuple
  * alias atoms are wrapped in __aliases__ tuple

  ## Examples

      iex> ast = Code.string_to_quoted!("cond do true -> 123 end")
      {:cond, [line: 1], [[do: [{:->, [line: 1], [[true], 987]}]]]}
      iex> normalize(ast)
      {:cond, [line: 1], [[do: [{:->, [line: 1], [[true], {:__block__, [], [987]}]}]]]}
  """
  @spec normalize(AST.t()) :: AST.t()
  def normalize(ast)

  def normalize({:case, meta, [condition, [do: clauses]]}) do
    {:case, meta, [condition, [do: normalize(clauses)]]}
  end

  def normalize({:cond, meta, [[do: clauses]]}) do
    {:cond, meta, [[do: normalize(clauses)]]}
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

  def normalize({:->, meta, [pattern, {:__block__, [], exprs}]}) do
    {:->, meta, [pattern, {:__block__, [], normalize(exprs)}]}
  end

  def normalize({:->, meta, [pattern, expr]}) do
    {:->, meta, [pattern, {:__block__, [], [normalize(expr)]}]}
  end

  def normalize({{:unquote, _meta_1, [marker]}, meta_2, children}) do
    {marker, meta_2, children}
  end

  def normalize(ast) when is_atom(ast) do
    if Reflection.alias?(ast) do
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
