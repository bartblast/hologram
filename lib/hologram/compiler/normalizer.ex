defmodule Hologram.Compiler.Normalizer do
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.Reflection

  @doc """
  Normalizes Elixir AST by ensuring that:
  * single expression blocks are wrapped in __block__ tuple
  * alias atoms are wrapped in __aliases__ tuple
  * unquote fragments are expanded

  ## Examples

      iex> ast = Code.string_to_quoted!("cond do true -> 123 end")
      {:cond, [line: 1], [[do: [{:->, [line: 1], [[true], 987]}]]]}
      iex> normalize(ast)
      {:cond, [line: 1], [[do: [{:->, [line: 1], [[true], {:__block__, [], [987]}]}]]]}
  """
  @spec normalize(AST.t()) :: AST.t()
  def normalize(ast)

  def normalize({:__aliases__, meta, [module]} = ast) do
    maybe_normalize_alias(module, meta, ast)
  end

  def normalize(ast) when is_atom(ast) do
    maybe_normalize_alias(ast, [alias: false], ast)
  end

  def normalize({:->, meta, [pattern, {:__block__, [], exprs}]}) do
    {:->, meta, [normalize(pattern), {:__block__, [], normalize(exprs)}]}
  end

  def normalize({:->, meta, [pattern, expr]}) do
    {:->, meta, [normalize(pattern), {:__block__, [], [normalize(expr)]}]}
  end

  def normalize({:case, meta, [condition, [do: clauses]]}) do
    {:case, meta, [normalize(condition), [do: normalize(clauses)]]}
  end

  def normalize({:cond, meta, [[do: clauses]]}) do
    {:cond, meta, [[do: normalize(clauses)]]}
  end

  def normalize(do: {:__block__, [], exprs}) do
    [do: {:__block__, [], normalize(exprs)}]
  end

  def normalize(do: expr) do
    [do: {:__block__, [], [normalize(expr)]}]
  end

  def normalize({{:unquote, _meta_1, [marker]}, meta_2, children}) do
    {marker, meta_2, normalize(children)}
  end

  def normalize(ast) when is_list(ast) do
    Enum.map(ast, &normalize/1)
  end

  def normalize(ast) when is_tuple(ast) do
    ast
    |> Tuple.to_list()
    |> normalize()
    |> List.to_tuple()
  end

  def normalize(ast), do: ast

  defp maybe_normalize_alias(module, meta, ast) do
    if Reflection.alias?(module) do
      segments = Helpers.alias_segments(module)
      {:__aliases__, meta, segments}
    else
      ast
    end
  end
end
