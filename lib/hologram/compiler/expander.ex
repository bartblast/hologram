defmodule Hologram.Compiler.Expander do
  alias Hologram.Compiler.{Helpers, Normalizer, Processor}
  alias Hologram.Compiler.IR.{MacroDefinition, RequireDirective}

  def expand_macro(%MacroDefinition{module: module, name: name}, params) do
    expand_macro(module, name, params)
  end

  def expand_macro(module, name, params) do
    expanded =
      apply(module, :"MACRO-#{name}", [__ENV__] ++ params)
      |> Normalizer.normalize()

    case expanded do
      {:__block__, [], exprs} ->
        exprs
      _ ->
        [expanded]
    end
  end

  def expand_macros(ast, requires) do
    expand_with_fun(ast, &expand_macros_in_expression(&1, requires))
  end

  defp expand_macros_in_expression({name, _, params} = expr, requires) do
    params = unless params, do: [], else: params
    macro_def = find_macro_definition(name, params, requires)

    if macro_def do
      expand_macro(macro_def, params)
    else
      expr
    end
  end

  defp expand_macros_in_expression(expr, _), do: expr

  defp expand_use_directive({:use, _, [{:__aliases__, _, module_segs}]}) do
    Helpers.module(module_segs)
    |> expand_macro(:__using__, [nil])
  end

  defp expand_use_directive(ast) do
    ast
  end

  def expand_use_directives(ast) do
    expand_with_fun(ast, &expand_use_directive/1)
  end

  defp expand_with_fun({:defmodule, line, [aliases, [do: {:__block__, _, exprs}]]}, fun) do
    expanded =
      Enum.reduce(exprs, [], fn expr, acc ->
        case fun.(expr) do
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
