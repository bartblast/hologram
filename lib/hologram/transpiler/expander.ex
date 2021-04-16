defmodule Hologram.Transpiler.Expander do
  alias Hologram.Transpiler.Parser

  def expand({:defmodule, line, [aliases, [do: ast]]}) do
    {:defmodule, line, [aliases, [do: expand(ast)]]}
  end

  def expand({:__block__, [], expressions}) do
    {:__block__, [], Enum.map(expressions, &expand/1)}
  end

  def expand({:use, _, [{:__aliases__, _, module}]}) do
    module =
      [:Elixir] ++ module
      |> Enum.join(".")
      |> String.to_existing_atom()

    module.module_info()[:compile][:source]
    |> Parser.parse_file!()
    |> aggregate_quotes()
  end

  def expand(ast) do
    ast
  end

  defp aggregate_quotes({:defmodule, _, [{:__aliases__, _, _}, [do: ast]]}) do
    aggregate_quotes(ast)
  end

  defp aggregate_quotes({:defmacro, _, [{:__using__, _, _}, [do: ast]]}) do
    aggregate_quotes(ast)
  end

  defp aggregate_quotes({:quote, _, [[do: ast]]}) do
    ast
  end

  defp aggregate_quotes(ast) do
    ast
  end
end
