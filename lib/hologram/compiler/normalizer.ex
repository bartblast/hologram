defmodule Hologram.Compiler.Normalizer do
  @moduledoc false

  alias Hologram.Compiler.AST
  alias Hologram.Compiler.Helpers
  alias Hologram.Reflection

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

  def normalize({:->, meta, [pattern, block]}) do
    {:->, meta, [normalize(pattern), normalize_block(block)]}
  end

  def normalize({:__aliases__, meta, [module]} = ast) do
    maybe_normalize_alias(module, meta, ast)
  end

  def normalize({marker, meta, [name, [do: block]]}) when marker in [:def, :defp] do
    {marker, meta, [normalize(name), [do: normalize_block(block)]]}
  end

  def normalize({:defmodule, meta, [name, [do: block]]}) do
    {:defmodule, meta, [normalize(name), [do: normalize_block(block)]]}
  end

  def normalize({:for, meta, parts}) when is_list(parts) do
    {:for, meta, Enum.map(parts, &normalize_comprehension_part/1)}
  end

  def normalize({:try, meta, [opts]}) when is_list(opts) do
    {:try, meta, [Enum.map(opts, &normalize_try_opt/1)]}
  end

  def normalize({{:unquote, _meta_1, [marker]}, meta_2, children}) do
    {marker, meta_2, normalize(children)}
  end

  def normalize({:with, meta, parts}) do
    {:with, meta, normalize_with_parts(parts)}
  end

  def normalize(ast) when is_atom(ast) do
    maybe_normalize_alias(ast, [alias: false], ast)
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

  defp normalize_block({:__block__, meta, exprs}) do
    normalized =
      exprs
      |> normalize()
      |> strip_non_tail_aliases()

    {:__block__, meta, normalized}
  end

  defp normalize_block(expr) do
    {:__block__, [], [normalize(expr)]}
  end

  defp normalize_comprehension_opt({:do, block}) do
    {:do, normalize_block(block)}
  end

  defp normalize_comprehension_opt(opt), do: normalize(opt)

  defp normalize_comprehension_part(opts) when is_list(opts) do
    Enum.map(opts, &normalize_comprehension_opt/1)
  end

  defp normalize_comprehension_part(part), do: normalize(part)

  defp normalize_try_opt({:after, block}) do
    {:after, normalize_block(block)}
  end

  defp normalize_try_opt({:do, block}) do
    {:do, normalize_block(block)}
  end

  defp normalize_try_opt(opt), do: normalize(opt)

  # `with` used as a variable name, e.g. {:with, meta, nil}
  defp normalize_with_parts(nil), do: nil

  defp normalize_with_parts([[{:do, body} | rest]]) do
    else_clauses =
      case rest do
        [] ->
          []

        [{:else, {:__block__, [], []}}] ->
          []

        [{:else, clauses}] ->
          clauses
      end

    [[{:do, normalize_block(body)}, {:else, Enum.map(else_clauses, &normalize/1)}]]
  end

  defp normalize_with_parts([clause | rest]) do
    [normalize(clause) | normalize_with_parts(rest)]
  end

  # Strips bare alias expressions from non-tail positions of a block.
  # The Elixir compiler stores function-body `import` statements as bare module atoms
  # in the debug info AST (e.g. `import Kernel, only: [+: 2]` becomes a bare `Kernel` atom).
  # After normalization these become `{:__aliases__, meta, segments}` tuples. They are dead code
  # (their values are discarded) and must be removed to prevent the call graph from
  # creating spurious module vertex edges.
  defp strip_non_tail_aliases(exprs)

  defp strip_non_tail_aliases([_expr] = exprs), do: exprs

  defp strip_non_tail_aliases([{:__aliases__, _meta, _segments} | rest]) do
    strip_non_tail_aliases(rest)
  end

  defp strip_non_tail_aliases([expr | rest]) do
    [expr | strip_non_tail_aliases(rest)]
  end

  defp strip_non_tail_aliases([]), do: []
end
