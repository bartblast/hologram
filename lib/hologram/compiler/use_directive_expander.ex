defmodule Hologram.Compiler.UseDirectiveExpander do
  alias Hologram.Compiler.{Helpers, MacroExpander}

  def expand({:defmodule, line, [aliases, [do: {:__block__, _, exprs}]]}) do
    expanded =
      Enum.reduce(exprs, [], fn expr, acc ->
        case expand(expr) do
          # expanded expression is returned wrapped in a list
          expr when is_list(expr) ->
            acc ++ expr

          # non-expandable expression
          expr ->
            acc ++ [expr]
        end
      end)

    {:defmodule, line, [aliases, [do: {:__block__, [], expanded}]]}
  end

  def expand({:use, _, [{:__aliases__, _, module_segs}]}) do
    Helpers.module(module_segs)
    |> MacroExpander.expand(:__using__, [nil])
  end

  def expand(ast) do
    ast
  end
end
