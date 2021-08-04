defmodule Hologram.Compiler.Expander do
  alias Hologram.Compiler.{Helpers, Normalizer, Parser, Processor}
  alias Hologram.Compiler.IR.{MacroDefinition, RequireDirective}

  @doc """
  Go through each module expression and expand recursively those which are expandable (e.g. use directive).
  """
  def expand({:defmodule, line, [aliases, [do: {:__block__, [], exprs}]]}) do
    expanded =
      Enum.reduce(exprs, [], fn expr, acc ->
        case expand(expr) do
          # expanded expression is returned wrapped in a list
          e when is_list(e) ->
            acc ++ e

          # non-expandable expression
          e ->
            acc ++ [e]
        end
      end)

    {:defmodule, line, [aliases, [do: {:__block__, [], expanded}]]}
  end

  def expand({:use, _, [{:__aliases__, _, module_segs}]}) do
    Helpers.module(module_segs)
    |> Helpers.module_source_path()
    |> Parser.parse_file!()
    |> Normalizer.normalize()
    |> aggregate_quotes()
  end

  def expand(ast) do
    ast
  end

  defp aggregate_quotes({:defmodule, _, [{:__aliases__, _, _}, [do: {:__block__, [], exprs}]]}) do
    aggregate_quotes_in_block(exprs)
  end

  defp aggregate_quotes({:defmacro, _, [{:__using__, _, _}, [do: {:__block__, [], exprs}]]}) do
    aggregate_quotes_in_block(exprs)
  end

  defp aggregate_quotes({:quote, _, [[do: {:__block__, [], exprs}]]}) do
    exprs
  end

  defp aggregate_quotes(_), do: []

  defp aggregate_quotes_in_block(exprs) do
    Enum.reduce(exprs, [], fn expr, acc ->
      acc ++ aggregate_quotes(expr)
    end)
  end
end
