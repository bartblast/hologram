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

  def normalize({:for, meta, parts}) when is_list(parts) do
    {:for, meta, Enum.map(parts, &normalize_comprehension_part/1)}
  end

  def normalize({marker, meta, [name, [do: {:__block__, [], exprs}]]})
      when marker in [:def, :defp] do
    {marker, meta, [name, [do: {:__block__, [], normalize(exprs)}]]}
  end

  def normalize({marker, meta, [name, [do: expr]]}) when marker in [:def, :defp] do
    {marker, meta, [name, [do: {:__block__, [], [normalize(expr)]}]]}
  end

  def normalize({:defmodule, meta, [name, [do: {:__block__, [], exprs}]]}) do
    {:defmodule, meta, [name, [do: {:__block__, [], normalize(exprs)}]]}
  end

  def normalize({:defmodule, meta, [name, [do: expr]]}) do
    {:defmodule, meta, [name, [do: {:__block__, [], [normalize(expr)]}]]}
  end

  def normalize({:try, meta, [opts]}) when is_list(opts) do
    {:try, meta, [Enum.map(opts, &maybe_normalize_do_block/1)]}
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

  defp maybe_normalize_do_block({:do, {:__block__, [], exprs}}) do
    {:do, {:__block__, [], normalize(exprs)}}
  end

  defp maybe_normalize_do_block({:do, expr}) do
    {:do, {:__block__, [], [normalize(expr)]}}
  end

  defp maybe_normalize_do_block(opt), do: normalize(opt)

  defp normalize_comprehension_part(opts) when is_list(opts) do
    Enum.map(opts, &maybe_normalize_do_block/1)
  end

  defp normalize_comprehension_part(part), do: normalize(part)
end
