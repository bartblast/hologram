defmodule Hologram.Compiler.MacrosExpander do
  alias Hologram.Compiler.IR.RequireDirective
  alias Hologram.Compiler.{MacroExpander, Processor}

  def expand({:defmodule, line, [aliases, [do: {:__block__, _, exprs}]]} = ast, requires) do
    expanded =
      Enum.reduce(exprs, [], fn expr, acc ->
        case expand(expr, requires) do
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

  def expand({name, _, params} = ast, requires) do
    params = unless params, do: [], else: params
    macro_def = find_macro_definition(name, params, requires)

    if macro_def do
      MacroExpander.expand(macro_def, params)
    else
      ast
    end
  end

  def expand(ast, _), do: ast

  defp find_macro_definition(name, params, requires) do
    require_directive =
      Enum.find(requires, fn %RequireDirective{module: module} ->
        macro_exported?(module, name, Enum.count(params))
      end)

    if require_directive do
      Processor.get_macro_definition(require_directive.module, name, params)
    else
      nil
    end
  end
end
