defmodule Hologram.Compiler.Expander do
  alias Hologram.Compiler.{Helpers, MacroExpander}

  def expand_use_directives(ast) do
    expand(ast, &expand_use_directive/1)
  end

  defp expand({:defmodule, line, [aliases, [do: {:__block__, _, exprs}]]}, function) do
    expanded =
      Enum.reduce(exprs, [], fn expr, acc ->
        case function.(expr) do
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

  defp expand_use_directive({:use, _, [{:__aliases__, _, module_segs}]}) do
    Helpers.module(module_segs)
    |> MacroExpander.expand(:__using__, [nil])
  end

  defp expand_use_directive(ast) do
    ast
  end
end
