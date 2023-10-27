defmodule Hologram.Compiler.Normalizer do
  alias Hologram.Commons.Reflection
  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Helpers

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

  def normalize({:->, meta, [pattern, block]}) do
    {:->, meta, [normalize(pattern), normalize_block(block)]}
  end

  def normalize({:for, meta, parts}) when is_list(parts) do
    parts
    |> Enum.map(&normalize_opts/1)
    |> then(&{:for, meta, &1})
  end

  def normalize({marker, meta, [name, opts]}) when marker in [:def, :defmodule, :defp] do
    opts
    |> normalize_opts()
    |> then(&{marker, meta, [normalize(name), &1]})
  end

  def normalize({:try, meta, [opts]}) do
    opts
    |> normalize_opts()
    |> then(&{:try, meta, [&1]})
  end

  def normalize({{:unquote, _meta_1, [marker]}, meta_2, children}) do
    children
    |> normalize()
    |> then(&{marker, meta_2, &1})
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
      module
      |> Helpers.alias_segments()
      |> then(&{:__aliases__, meta, &1})
    else
      ast
    end
  end

  defp normalize_block({:__block__, meta, exprs}) do
    exprs
    |> normalize()
    |> then(&{:__block__, meta, &1})
  end

  defp normalize_block(expr), do: normalize_block({:__block__, [], [expr]})

  defp normalize_opts(opts) when is_list(opts) do
    Enum.map(opts, fn
      {key, block} when key in ~w[after do]a ->
        block
        |> normalize_block()
        |> then(&{key, &1})

      # key in ~w[catch else rescue]a
      opt ->
        normalize(opt)
    end)
  end

  defp normalize_opts(part), do: normalize(part)
end
