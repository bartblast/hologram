defmodule Hologram.Transpiler.Expander do
  alias Hologram.Transpiler.Helpers
  alias Hologram.Transpiler.Normalizer
  alias Hologram.Transpiler.Parser

  def expand({:defmodule, line, [aliases, [do: {:__block__, [], exprs}]]}) do
    expanded =
      Enum.reduce(exprs, [], fn expr, acc ->
        case expand(expr) do
          e when is_list(e) ->
            acc ++ e
          e ->
            acc ++ [e]
        end
      end)

    {:defmodule, line, [aliases, [do: {:__block__, [], expanded}]]}
  end

  def expand({:use, _, [{:__aliases__, _, module}]}) do
    Helpers.fully_qualified_module(module)
    |> apply(:module_info, [])
    |> get_in([:compile, :source])
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

  defp aggregate_quotes_in_block(exprs) do
    Enum.reduce(exprs, [], fn expr, acc ->
      acc ++ aggregate_quotes(expr)
    end)
  end
end
